import Metal
import MetalKit
import QuartzCore
import UIKit
import Display
import IOSurface

final class LiquidGlassRenderer: NSObject {

    private weak var metalLayer: CAMetalLayer?
    private weak var sourceView: UIView?

    private let context: MetalContext
    private let texturePool: TexturePool
    private var backgroundCapture: BackgroundCapture?
    private var backgroundCaptureDraw: BackgroundCaptureDraw?
    private let gaussianWeights: GaussianWeights

    private var displayLink: SharedDisplayLinkDriver.Link?
    private(set) var isRendering: Bool = false

    private let maxFramesInFlight: UInt64 = 3
    private var frameCounter: UInt64 = 0
    private var lastCompletedFrame: UInt64 = 0
    private var currentBufferIndex: Int = 0

    private var isShuttingDown: Bool = false

    var configuration: LiquidGlassConfiguration = LiquidGlassConfiguration()
    var continuousUpdate: Bool = false

    private var needsRender: Bool = true

    private var lastViewFrame: CGRect = .zero
    private var lastSourceBounds: CGRect = .zero

    private(set) var currentQuality: QualityLevel

    init?(metalLayer: CAMetalLayer, sourceView: UIView?) {
        guard let context = MetalContext.shared else {
            return nil
        }

        self.context = context
        self.metalLayer = metalLayer
        self.sourceView = sourceView

        self.texturePool = TexturePool(device: context.device)
        self.gaussianWeights = GaussianWeights(device: context.device)

        self.currentQuality = configuration.quality ?? context.recommendedQuality

        super.init()
        setupNotifications()
    }

    deinit {
        stopRendering()
    }

    func startRendering() {
        guard !isRendering else { return }

        displayLink = SharedDisplayLinkDriver.shared.add { [weak self] _ in
            self?.render()
        }
        displayLink?.isPaused = false
        isRendering = true
    }

    func stopRendering() {
        guard isRendering else { return }

        isShuttingDown = true

        displayLink?.isPaused = true
        displayLink?.invalidate()
        displayLink = nil
        isRendering = false

        waitForGPUCompletion()

        isShuttingDown = false
    }

    private func waitForGPUCompletion() {
        guard frameCounter > lastCompletedFrame else { return }

        if let flushBuffer = context.commandQueue.makeCommandBuffer() {
            flushBuffer.commit()
            flushBuffer.waitUntilCompleted()
        }
    }

    func setNeedsRender() {
        needsRender = true
    }

    func updateSourceView(_ view: UIView?) {
        sourceView = view
        backgroundCapture?.invalidateCache()
        backgroundCaptureDraw?.invalidateCache()
        setNeedsRender()
    }

    private func getBackgroundCapture() -> BackgroundCapture {
        if backgroundCapture == nil {
            backgroundCapture = BackgroundCapture(device: context.device)
        }
        return backgroundCapture!
    }

    private func getBackgroundCaptureDraw() -> BackgroundCaptureDraw {
        if backgroundCaptureDraw == nil {
            backgroundCaptureDraw = BackgroundCaptureDraw(device: context.device)
        }
        return backgroundCaptureDraw!
    }

    func updateConfiguration(_ config: LiquidGlassConfiguration) {
        configuration = config
        currentQuality = config.quality ?? context.recommendedQuality
        gaussianWeights.invalidateCache()
        setNeedsRender()
    }

    private func render() {
        guard !isShuttingDown else { return }
        guard shouldRender() else { return }

        let framesInFlight = frameCounter - lastCompletedFrame
        guard framesInFlight < maxFramesInFlight else { return }

        guard let metalLayer = metalLayer,
              let drawable = metalLayer.nextDrawable() else {
            return
        }

        frameCounter += 1
        let thisFrameValue = frameCounter

        autoreleasepool {
            performRender(to: drawable, frameValue: thisFrameValue)
        }

        needsRender = false
        currentBufferIndex = Int(thisFrameValue % maxFramesInFlight)
    }

    private func shouldRender() -> Bool {
        if continuousUpdate { return true }

        if needsRender { return true }

        if let layer = metalLayer {
            let currentFrame = layer.frame
            if currentFrame != lastViewFrame {
                lastViewFrame = currentFrame
                return true
            }
        }

        if let source = sourceView {
            let currentBounds = source.bounds
            if currentBounds != lastSourceBounds {
                lastSourceBounds = currentBounds
                return true
            }
        }

        return false
    }

    private func performRender(to drawable: CAMetalDrawable, frameValue: UInt64) {
        guard let metalLayer = metalLayer,
              let sourceView = sourceView else {
            return
        }

        let viewFrame = metalLayer.frame
        let captureRegion = calculateCaptureRegion(viewFrame: viewFrame, in: sourceView)

        let _ = metalLayer.contentsScale

        let renderScale = currentQuality.renderScale

        let sourceTexture: MTLTexture
        var capturedSurface: IOSurface? = nil

        switch configuration.captureMethod {
        case .ioSurface:
            guard let captureResult = getBackgroundCapture().captureTexture(
                from: sourceView,
                region: captureRegion,
                scale: renderScale,
                excludedViews: []
            ) else {
                return
            }
            sourceTexture = captureResult.texture
            capturedSurface = captureResult.surface

        case .drawHierarchy:
            guard let texture = getBackgroundCaptureDraw().captureTexture(
                from: sourceView,
                region: captureRegion,
                scale: renderScale,
                excludedViews: []
            ) else {
                return
            }
            sourceTexture = texture
        }

        let effectiveRadius = configuration.effectiveBlurRadius(for: currentQuality)
        let effectiveSigma = Float(configuration.effectiveSigma)

        guard let weightsBuffer = gaussianWeights.weightsBuffer(
            radius: effectiveRadius,
            sigma: effectiveSigma
        ) else {
            return
        }

        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            return
        }

        let textureWidth = sourceTexture.width
        let textureHeight = sourceTexture.height

        guard let intermediateTexture1 = texturePool.acquire(width: textureWidth, height: textureHeight),
              let intermediateTexture2 = texturePool.acquire(width: textureWidth, height: textureHeight) else {
            return
        }

        var blurUniforms = BlurUniforms(
            texelSize: SIMD2<Float>(1.0 / Float(textureWidth), 1.0 / Float(textureHeight)),
            blurRadius: Int32(effectiveRadius),
            padding: 0
        )

        encodeBlurPass(
            commandBuffer: commandBuffer,
            sourceTexture: sourceTexture,
            destinationTexture: intermediateTexture1,
            uniforms: &blurUniforms,
            weightsBuffer: weightsBuffer,
            isHorizontal: false
        )

        encodeBlurPass(
            commandBuffer: commandBuffer,
            sourceTexture: intermediateTexture1,
            destinationTexture: intermediateTexture2,
            uniforms: &blurUniforms,
            weightsBuffer: weightsBuffer,
            isHorizontal: true
        )

        let outputSize = SIMD2<Float>(Float(drawable.texture.width), Float(drawable.texture.height))
        encodeInnerShadowPass(
            commandBuffer: commandBuffer,
            sourceTexture: intermediateTexture2,
            destinationTexture: intermediateTexture1,
            viewSize: outputSize
        )

        encodeRefractionCompositePass(
            commandBuffer: commandBuffer,
            sourceTexture: intermediateTexture1,
            destinationTexture: drawable.texture,
            viewSize: outputSize
        )

        commandBuffer.encodeSignalEvent(context.sharedEvent, value: frameValue)

        commandBuffer.present(drawable)

        context.sharedEvent.notify(
            context.eventListener,
            atValue: frameValue
        ) { [weak self] _, value in
            guard let self = self else { return }

            self.lastCompletedFrame = value

            self.texturePool.release(intermediateTexture1)
            self.texturePool.release(intermediateTexture2)

            if let surface = capturedSurface {
                self.getBackgroundCapture().releaseSurface(surface)
            }
        }

        commandBuffer.commit()
    }

    private func encodeBlurPass(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        destinationTexture: MTLTexture,
        uniforms: inout BlurUniforms,
        weightsBuffer: MTLBuffer,
        isHorizontal: Bool
    ) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .dontCare
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let pipelineState = isHorizontal ? context.horizontalBlurPipelineState : context.verticalBlurPipelineState

        encoder.setRenderPipelineState(pipelineState!)
        encoder.setVertexBuffer(context.quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BlurUniforms>.size, index: 0)
        encoder.setFragmentBuffer(weightsBuffer, offset: 0, index: 1)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    private func encodeInnerShadowPass(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        destinationTexture: MTLTexture,
        viewSize: SIMD2<Float>
    ) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .dontCare
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let scale = metalLayer?.contentsScale ?? 1
        let innerShadowPadding = SIMD2<Float>(
            Float(configuration.shapePadding.x * scale),
            Float(configuration.shapePadding.y * scale)
        )

        var innerShadowUniforms = InnerShadowUniforms(
            viewSize: viewSize,
            cornerRadius: Float(configuration.cornerRadius * scale),
            padding1: 0,
            shapePadding: innerShadowPadding,
            morphScale: SIMD2<Float>(
                Float(configuration.morphScale.x),
                Float(configuration.morphScale.y)
            )
        )

        encoder.setRenderPipelineState(context.innerShadowPipelineState)
        encoder.setVertexBuffer(context.quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentBytes(&innerShadowUniforms, length: MemoryLayout<InnerShadowUniforms>.size, index: 0)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    private func encodeCompositePass(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        destinationTexture: MTLTexture,
        viewSize: SIMD2<Float>
    ) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let compositeScale = metalLayer?.contentsScale ?? 1
        let compositePadding = SIMD2<Float>(
            Float(configuration.shapePadding.x * compositeScale),
            Float(configuration.shapePadding.y * compositeScale)
        )
        var compositeUniforms = CompositeUniforms(
            viewSize: viewSize,
            cornerRadius: Float(configuration.cornerRadius * compositeScale),
            opacity: Float(configuration.opacity),
            shapePadding: compositePadding
        )

        encoder.setRenderPipelineState(context.compositePipelineState)
        encoder.setVertexBuffer(context.quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentBytes(&compositeUniforms, length: MemoryLayout<CompositeUniforms>.size, index: 0)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    private func encodeRefractionCompositePass(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        destinationTexture: MTLTexture,
        viewSize: SIMD2<Float>
    ) {
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = destinationTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        let scale = metalLayer?.contentsScale ?? 1
        let refractionPadding = SIMD2<Float>(
            Float(configuration.shapePadding.x * scale),
            Float(configuration.shapePadding.y * scale)
        )

        var tintR: CGFloat = 0, tintG: CGFloat = 0, tintB: CGFloat = 0, tintA: CGFloat = 0
        configuration.tint.getRed(&tintR, green: &tintG, blue: &tintB, alpha: &tintA)

        var glareFarR: CGFloat = 0, glareFarG: CGFloat = 0, glareFarB: CGFloat = 0, glareFarA: CGFloat = 0
        configuration.glareFarsideColor.getRed(&glareFarR, green: &glareFarG, blue: &glareFarB, alpha: &glareFarA)

        var glareNearR: CGFloat = 0, glareNearG: CGFloat = 0, glareNearB: CGFloat = 0, glareNearA: CGFloat = 0
        configuration.glareNearsideColor.getRed(&glareNearR, green: &glareNearG, blue: &glareNearB, alpha: &glareNearA)

        var refractionUniforms = RefractionUniforms(
            viewSize: viewSize,
            cornerRadius: Float(configuration.cornerRadius * scale),
            opacity: Float(configuration.opacity),
            refThickness: Float(configuration.refThickness * scale),
            refFactor: Float(configuration.refFactor),
            fresnelRange: Float(configuration.fresnelRange),
            fresnelFactor: Float(configuration.fresnelFactor),
            fresnelHardness: Float(configuration.fresnelHardness),
            glareRange: Float(configuration.glareRange),
            glareFactor: Float(configuration.glareFactor),
            glareHardness: Float(configuration.glareHardness),
            glareConvergence: Float(configuration.glareConvergence),
            glareAngle: Float(configuration.glareAngle),
            glareOppositeFactor: Float(configuration.glareOppositeFactor),
            refDispersion: Float(configuration.refDispersion),
            useReflection: configuration.useReflection ? 1.0 : 0.0,
            morphScale: SIMD2<Float>(
                Float(configuration.morphScale.x),
                Float(configuration.morphScale.y)
            ),
            shapePadding: refractionPadding,
            tint: SIMD4<Float>(Float(tintR), Float(tintG), Float(tintB), Float(tintA)),
            glareFarsideColor: SIMD4<Float>(Float(glareFarR), Float(glareFarG), Float(glareFarB), Float(glareFarA)),
            glareNearsideColor: SIMD4<Float>(Float(glareNearR), Float(glareNearG), Float(glareNearB), Float(glareNearA))
        )

        encoder.setRenderPipelineState(context.refractionCompositePipelineState)
        encoder.setVertexBuffer(context.quadVertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentBytes(&refractionUniforms, length: MemoryLayout<RefractionUniforms>.size, index: 0)

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }

    private func calculateCaptureRegion(viewFrame: CGRect, in sourceView: UIView) -> CGRect {
        guard let metalLayer = metalLayer,
              let superlayer = metalLayer.superlayer else {
            let padding = configuration.effectiveCapturePadding
            return viewFrame.insetBy(dx: -padding.x, dy: -padding.y)
        }

        var frameInSource = viewFrame

        if let superviewLayer = superlayer.delegate as? UIView {
            frameInSource = superviewLayer.convert(viewFrame, to: sourceView)
        } else {
            var currentLayer: CALayer? = superlayer
            while let layer = currentLayer {
                if let view = layer.delegate as? UIView {
                    let layerFrameInView = layer.convert(viewFrame, to: view.layer)
                    frameInSource = view.convert(layerFrameInView, to: sourceView)
                    break
                }
                currentLayer = layer.superlayer
            }
        }

        let padding = configuration.effectiveCapturePadding
        return frameInSource.insetBy(dx: -padding.x, dy: -padding.y)
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        texturePool.purge()
        backgroundCapture?.purge()
        backgroundCaptureDraw?.purge()
        gaussianWeights.invalidateCache()
    }

    @objc private func handleAppWillResignActive() {
        stopRendering()
        texturePool.cleanupUnusedTextures()
    }

    @objc private func handleAppDidBecomeActive() {
        if metalLayer?.superlayer != nil {
            startRendering()
        }
    }
}
