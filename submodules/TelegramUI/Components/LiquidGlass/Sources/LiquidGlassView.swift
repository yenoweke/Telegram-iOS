import UIKit
import Metal
import QuartzCore

public class LiquidGlassView: UIView {

    public var configuration: LiquidGlassConfiguration = LiquidGlassConfiguration() {
        didSet {
            renderer?.updateConfiguration(configuration)
        }
    }

    public weak var sourceView: UIView? {
        didSet {
            renderer?.updateSourceView(sourceView ?? superview)
        }
    }

    public var continuousUpdate: Bool = false {
        didSet {
            renderer?.continuousUpdate = continuousUpdate
        }
    }

    public var isRendering: Bool {
        renderer?.isRendering ?? false
    }

    public var currentQuality: QualityLevel {
        renderer?.currentQuality ?? .medium
    }

    private var renderer: LiquidGlassRenderer?

    public override class var layerClass: AnyClass {
        CAMetalLayer.self
    }

    public var metalLayer: CAMetalLayer {
        layer as! CAMetalLayer
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    public convenience init(configuration: LiquidGlassConfiguration) {
        self.init(frame: .zero)
        self.configuration = configuration
    }

    private func commonInit() {
        clipsToBounds = false

        metalLayer.masksToBounds = false
        metalLayer.isOpaque = false
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = UIScreen.main.scale
        metalLayer.contentsGravity = .center

        backgroundColor = .clear
        isOpaque = false

        metalLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "contentsScale": NSNull()
        ]
    }

    public override func didMoveToSuperview() {
        super.didMoveToSuperview()

        if superview != nil {
            setupRenderer()
            renderer?.startRendering()
        } else {
            renderer?.stopRendering()
            renderer = nil
        }
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()

        if let window = window {
            metalLayer.contentsScale = window.screen.scale
            renderer?.setNeedsRender()
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        let scale = metalLayer.contentsScale
        let paddingX = configuration.shapePadding.x * scale
        let paddingY = configuration.shapePadding.y * scale
        let drawableSize = CGSize(
            width: bounds.width * scale + paddingX * 2,
            height: bounds.height * scale + paddingY * 2
        )

        if metalLayer.drawableSize != drawableSize {
            metalLayer.drawableSize = drawableSize
            renderer?.setNeedsRender()
        }
    }

    public func invalidateBackground() {
        renderer?.setNeedsRender()
    }

    public func pauseRendering() {
        renderer?.stopRendering()
    }

    public func resumeRendering() {
        renderer?.startRendering()
    }

    public func setBlurRadius(_ radius: CGFloat, animated: Bool = false) {
        configuration.blurRadius = radius
        // TODO: Implement animation via CADisplayLink interpolation
    }

    public func setSigma(_ sigma: CGFloat) {
        configuration.sigma = sigma
    }

    public func setMorphScale(_ scale: CGPoint) {
        configuration.morphScale = scale
    }

    private func setupRenderer() {
        guard renderer == nil else { return }

        let effectiveSourceView = sourceView ?? superview
        renderer = LiquidGlassRenderer(
            metalLayer: metalLayer,
            sourceView: effectiveSourceView
        )
        renderer?.configuration = configuration
        renderer?.continuousUpdate = continuousUpdate
    }
}
