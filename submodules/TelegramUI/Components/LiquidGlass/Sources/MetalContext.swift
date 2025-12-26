import Metal
import UIKit

private final class BundleMarker: NSObject {}

final class MetalContext {

    static let shared: MetalContext? = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("MetalContext: cannot MTLCreateSystemDefaultDevice")
            return nil
        }
        return MetalContext(device: device)
    }()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let library: MTLLibrary

    private(set) var horizontalBlurPipelineState: MTLRenderPipelineState!
    private(set) var verticalBlurPipelineState: MTLRenderPipelineState!
    private(set) var compositePipelineState: MTLRenderPipelineState!
    private(set) var refractionCompositePipelineState: MTLRenderPipelineState!
    private(set) var innerShadowPipelineState: MTLRenderPipelineState!

    private(set) var quadVertexBuffer: MTLBuffer!

    let recommendedQuality: QualityLevel

    let sharedEvent: MTLSharedEvent
    let eventListener: MTLSharedEventListener
    private let eventNotificationQueue: DispatchQueue

    private init?(device: MTLDevice) {
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = commandQueue

        let mainBundle = Bundle(for: BundleMarker.self)
        guard let path = mainBundle.path(forResource: "LiquidGlassMetalSourcesBundle", ofType: "bundle") else {
            print("MetalContext: cannot find LiquidGlassMetalSourcesBundle")
            return nil
        }
        guard let bundle = Bundle(path: path) else {
            print("MetalContext: cannot load bundle at path \(path)")
            return nil
        }
        guard let library = try? device.makeDefaultLibrary(bundle: bundle) else {
            print("MetalContext: cannot makeDefaultLibrary from bundle")
            return nil
        }
        self.library = library

        self.recommendedQuality = Self.detectQualityLevel(device: device)

        guard let sharedEvent = device.makeSharedEvent() else {
            print("MetalContext: cannot makeSharedEvent")
            return nil
        }
        self.sharedEvent = sharedEvent

        self.eventNotificationQueue = DispatchQueue(
            label: "org.telegram.liquidglass.sync",
            qos: .userInitiated
        )
        self.eventListener = MTLSharedEventListener(
            dispatchQueue: self.eventNotificationQueue
        )

        do {
            try setupPipelineStates()
            setupQuadVertexBuffer()
        } catch {
            print("MetalContext: Failed to setup pipeline states: \(error)")
            return nil
        }
    }

    private func setupPipelineStates() throws {
        let vertexFunction = library.makeFunction(name: "vertexPassthrough")
        let horizontalBlurFunction = library.makeFunction(name: "gaussianBlurHorizontal")
        let verticalBlurFunction = library.makeFunction(name: "gaussianBlurVertical")
        let compositeFunction = library.makeFunction(name: "compositeFragment")

        let blurPipelineDescriptor = MTLRenderPipelineDescriptor()
        blurPipelineDescriptor.vertexFunction = vertexFunction
        blurPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        blurPipelineDescriptor.fragmentFunction = horizontalBlurFunction
        horizontalBlurPipelineState = try device.makeRenderPipelineState(descriptor: blurPipelineDescriptor)

        blurPipelineDescriptor.fragmentFunction = verticalBlurFunction
        verticalBlurPipelineState = try device.makeRenderPipelineState(descriptor: blurPipelineDescriptor)

        let compositePipelineDescriptor = MTLRenderPipelineDescriptor()
        compositePipelineDescriptor.vertexFunction = vertexFunction
        compositePipelineDescriptor.fragmentFunction = compositeFunction
        compositePipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        compositePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        compositePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        compositePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        compositePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        compositePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        compositePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        compositePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        compositePipelineState = try device.makeRenderPipelineState(descriptor: compositePipelineDescriptor)

        let refractionCompositeFunction = library.makeFunction(name: "refractionCompositeFragment")

        let refractionPipelineDescriptor = MTLRenderPipelineDescriptor()
        refractionPipelineDescriptor.vertexFunction = vertexFunction
        refractionPipelineDescriptor.fragmentFunction = refractionCompositeFunction
        refractionPipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        refractionPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        refractionPipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        refractionPipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        refractionPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        refractionPipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        refractionPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        refractionPipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        refractionCompositePipelineState = try device.makeRenderPipelineState(descriptor: refractionPipelineDescriptor)

        let innerShadowFunction = library.makeFunction(name: "innerShadowFragment")

        let innerShadowDescriptor = MTLRenderPipelineDescriptor()
        innerShadowDescriptor.vertexFunction = vertexFunction
        innerShadowDescriptor.fragmentFunction = innerShadowFunction
        innerShadowDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        innerShadowDescriptor.colorAttachments[0].isBlendingEnabled = false

        innerShadowPipelineState = try device.makeRenderPipelineState(descriptor: innerShadowDescriptor)
    }

    private func setupQuadVertexBuffer() {
        let vertices: [Vertex] = [
            Vertex(position: SIMD2<Float>(-1, -1), texCoord: SIMD2<Float>(0, 1)), // bottom-left
            Vertex(position: SIMD2<Float>( 1, -1), texCoord: SIMD2<Float>(1, 1)), // bottom-right
            Vertex(position: SIMD2<Float>(-1,  1), texCoord: SIMD2<Float>(0, 0)), // top-left
            Vertex(position: SIMD2<Float>( 1,  1), texCoord: SIMD2<Float>(1, 0)), // top-right
        ]

        quadVertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )
    }

    private static func detectQualityLevel(device: MTLDevice) -> QualityLevel {
        // Check GPU family support for iOS
        if #available(iOS 13.0, *) {
            if device.supportsFamily(.apple7) {
                return .ultra  // A14 Bionic and later (iPhone 12+)
            } else if device.supportsFamily(.apple5) {
                return .high   // A12 Bionic and later (iPhone XS+)
            } else if device.supportsFamily(.apple4) {
                return .medium // A11 (iPhone 8/X)
            } else if device.supportsFamily(.apple3) {
                return .medium // A9/A10 (iPhone 6s/7)
            }
        }
        return .high
    }
}

public enum QualityLevel: Int, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
    case ultra = 3

    var maxBlurRadius: Int {
        switch self {
        case .low: return 16
        case .medium: return 32
        case .high: return 64
        case .ultra: return 100
        }
    }

    var renderScale: CGFloat {
        switch self {
        case .low: return 0.5
        case .medium: return 0.75
        case .high: return 1.0
        case .ultra: return 1.0
        }
    }

    var description: String {
        switch self {
        case .low: return "Low (iPhone 6s/7)"
        case .medium: return "Medium (iPhone 8/X)"
        case .high: return "High (iPhone 11+)"
        case .ultra: return "Ultra (iPhone 12 Pro+)"
        }
    }
}
