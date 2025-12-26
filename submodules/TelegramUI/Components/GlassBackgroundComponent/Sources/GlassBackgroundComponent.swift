import Foundation
import UIKit
import Display
import ComponentFlow
import ComponentDisplayAdapters
import UIKitRuntimeUtils
import CoreImage
import AppBundle
import LiquidGlass

private final class ContentContainer: UIView {
    private let maskContentView: UIView
    
    init(maskContentView: UIView) {
        self.maskContentView = maskContentView
        
        super.init(frame: CGRect())
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let result = super.hitTest(point, with: event) else {
            return nil
        }
        if result === self {
            if let gestureRecognizers = self.gestureRecognizers, !gestureRecognizers.isEmpty {
                return result
            }
            return nil
        }
        return result
    }
    
    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        
        if let subview = subview as? GlassBackgroundView.ContentView {
            self.maskContentView.addSubview(subview.tintMask)
        }
    }
    
    override func willRemoveSubview(_ subview: UIView) {
        super.willRemoveSubview(subview)
        
        if let subview = subview as? GlassBackgroundView.ContentView {
            subview.tintMask.removeFromSuperview()
        }
    }
}

public class GlassBackgroundView: UIView {
    public protocol ContentView: UIView {
        var tintMask: UIView { get }
    }
    
    open class ContentLayer: SimpleLayer {
        public var targetLayer: CALayer?
        
        override init() {
            super.init()
        }
        
        override init(layer: Any) {
            super.init(layer: layer)
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override public var position: CGPoint {
            get {
                return super.position
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.position = value
                }
                super.position = value
            }
        }
        
        override public var bounds: CGRect {
            get {
                return super.bounds
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.bounds = value
                }
                super.bounds = value
            }
        }
        
        override public var anchorPoint: CGPoint {
            get {
                return super.anchorPoint
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.anchorPoint = value
                }
                super.anchorPoint = value
            }
        }
        
        override public var anchorPointZ: CGFloat {
            get {
                return super.anchorPointZ
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.anchorPointZ = value
                }
                super.anchorPointZ = value
            }
        }
        
        override public var opacity: Float {
            get {
                return super.opacity
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.opacity = value
                }
                super.opacity = value
            }
        }
        
        override public var sublayerTransform: CATransform3D {
            get {
                return super.sublayerTransform
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.sublayerTransform = value
                }
                super.sublayerTransform = value
            }
        }
        
        override public var transform: CATransform3D {
            get {
                return super.transform
            } set(value) {
                if let targetLayer = self.targetLayer {
                    targetLayer.transform = value
                }
                super.transform = value
            }
        }
        
        override public func add(_ animation: CAAnimation, forKey key: String?) {
            if let targetLayer = self.targetLayer {
                targetLayer.add(animation, forKey: key)
            }
            
            super.add(animation, forKey: key)
        }
        
        override public func removeAllAnimations() {
            if let targetLayer = self.targetLayer {
                targetLayer.removeAllAnimations()
            }
            
            super.removeAllAnimations()
        }
        
        override public func removeAnimation(forKey: String) {
            if let targetLayer = self.targetLayer {
                targetLayer.removeAnimation(forKey: forKey)
            }
            
            super.removeAnimation(forKey: forKey)
        }
    }
    
    public final class ContentColorView: UIView, ContentView {
        override public static var layerClass: AnyClass {
            return ContentLayer.self
        }
        
        public let tintMask: UIView
        
        override public init(frame: CGRect) {
            self.tintMask = UIView()
            
            super.init(frame: CGRect())
            
            self.tintMask.tintColor = .black
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    public final class ContentImageView: UIImageView, ContentView {
        override public static var layerClass: AnyClass {
            return ContentLayer.self
        }
        
        private let tintImageView: UIImageView
        public var tintMask: UIView {
            return self.tintImageView
        }
        
        override public var image: UIImage? {
            didSet {
                self.tintImageView.image = self.image
            }
        }
        
        override public var tintColor: UIColor? {
            didSet {
                if self.tintColor != oldValue {
                    self.setMonochromaticEffect(tintColor: self.tintColor)
                }
            }
        }
        
        override public init(frame: CGRect) {
            self.tintImageView = UIImageView()
            
            super.init(frame: CGRect())
            
            self.tintImageView.tintColor = .black
        }
        
        override public init(image: UIImage?) {
            self.tintImageView = UIImageView()
            
            super.init(image: image)
            
            self.tintImageView.image = image
            self.tintImageView.tintColor = .black
        }
        
        override public init(image: UIImage?, highlightedImage: UIImage?) {
            self.tintImageView = UIImageView()
            
            super.init(image: image, highlightedImage: highlightedImage)
            
            self.tintImageView.image = image
            self.tintImageView.tintColor = .black
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    public struct TintColor: Equatable {
        public enum Kind {
            case panel
            case custom
        }
        
        public let kind: Kind
        public let color: UIColor
        public let innerColor: UIColor?
        
        public init(kind: Kind, color: UIColor, innerColor: UIColor? = nil) {
            self.kind = kind
            self.color = color
            self.innerColor = innerColor
        }
    }
    
    public enum Shape: Equatable {
        case roundedRect(cornerRadius: CGFloat)
    }
    
    private final class ClippingShapeContext {
        let view: UIView
        
        private(set) var shape: Shape?
        
        init(view: UIView) {
            self.view = view
        }
        
        func update(shape: Shape, size: CGSize, transition: ComponentTransition) {
            self.shape = shape
            
            switch shape {
            case let .roundedRect(cornerRadius):
                transition.setCornerRadius(layer: self.view.layer, cornerRadius: cornerRadius)
            }
        }
    }
    
    public struct Params: Equatable {
        public let shape: Shape
        public let isDark: Bool
        public let tintColor: TintColor
        public let isInteractive: Bool
        
        init(shape: Shape, isDark: Bool, tintColor: TintColor, isInteractive: Bool) {
            self.shape = shape
            self.isDark = isDark
            self.tintColor = tintColor
            self.isInteractive = isInteractive
        }
    }
    
    private let backgroundNode: NavigationBackgroundNode?

    private let nativeView: UIVisualEffectView?
    private let nativeViewClippingContext: ClippingShapeContext?
    private let nativeParamsView: EffectSettingsContainerView?

    private let foregroundView: UIImageView?
    private let shadowView: UIImageView?

    private var liquidGlassView: LiquidGlassView?

    private let maskContainerView: UIView
    public let maskContentView: UIView
    private let contentContainer: ContentContainer

    private var innerBackgroundView: UIView?
    
    public var contentView: UIView {
        if let nativeView = self.nativeView {
            return nativeView.contentView
        } else {
            return self.contentContainer
        }
    }
    
    public private(set) var params: Params?

    public enum Mode {
        case chat
        case chatList
    }

    private var mode: Mode?

    public static var useCustomGlassImpl: Bool = false

    private struct Components {
        let backgroundNode: NavigationBackgroundNode?
        let nativeView: UIVisualEffectView?
        let nativeViewClippingContext: ClippingShapeContext?
        let nativeParamsView: EffectSettingsContainerView?
        let foregroundView: UIImageView?
        let shadowView: UIImageView?
        let liquidGlassView: LiquidGlassView?
        let maskContainerView: UIView
        let maskContentView: UIView
        let contentContainer: ContentContainer
    }

    private static func prepareComponents(mode: Mode?) -> Components {
        let backgroundNode: NavigationBackgroundNode?
        let nativeView: UIVisualEffectView?
        let nativeViewClippingContext: ClippingShapeContext?
        let nativeParamsView: EffectSettingsContainerView?
        let foregroundView: UIImageView?
        let shadowView: UIImageView?
        let liquidGlassView: LiquidGlassView?

        let useLiquidGlass = mode != nil

        if #available(iOS 26.0, *), !GlassBackgroundView.useCustomGlassImpl {
            backgroundNode = nil

            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = false
            let nativeViewInstance = UIVisualEffectView(effect: glassEffect)
            let clippingContext = ClippingShapeContext(view: nativeViewInstance)
            nativeViewClippingContext = clippingContext
            nativeView = nativeViewInstance

            let nativeParamsViewInstance = EffectSettingsContainerView(frame: CGRect())
            nativeParamsView = nativeParamsViewInstance

            nativeParamsViewInstance.addSubview(nativeViewInstance)

            foregroundView = nil
            shadowView = nil
            liquidGlassView = nil
        } else if useLiquidGlass && LiquidGlassCapability.isDeviceSupported {
            backgroundNode = nil
            nativeView = nil
            nativeViewClippingContext = nil
            nativeParamsView = nil
            foregroundView = nil
            shadowView = nil

            var config = LiquidGlassConfiguration()
            config.blurRadius = 10.0
            config.refThickness = 20.0
            config.refFactor = 1.0
            config.useReflection = true
            config.shapePadding = CGPoint(x: 10.0, y: 10.0)
            config.capturePadding = CGPoint(x: 0.0, y: 0.0)
            config.cornerRadius = 20.0
            config.glareFactor = 0.0
            config.fresnelFactor = 0.1

            let liquidGlass = LiquidGlassView(configuration: config)
            liquidGlass.sourceView = nil
            liquidGlassView = liquidGlass
        } else {
            let backgroundNodeInstance = NavigationBackgroundNode(color: .black, enableBlur: true, customBlurRadius: 8.0)
            backgroundNode = backgroundNodeInstance
            nativeView = nil
            nativeViewClippingContext = nil
            nativeParamsView = nil
            foregroundView = UIImageView()
            shadowView = UIImageView()
            liquidGlassView = nil
        }

        let maskContainerView = UIView()
        maskContainerView.backgroundColor = .white
        if let filter = CALayer.luminanceToAlpha() {
            maskContainerView.layer.filters = [filter]
        }

        let maskContentView = UIView()
        maskContainerView.addSubview(maskContentView)

        let contentContainer = ContentContainer(maskContentView: maskContentView)

        return Components(
            backgroundNode: backgroundNode,
            nativeView: nativeView,
            nativeViewClippingContext: nativeViewClippingContext,
            nativeParamsView: nativeParamsView,
            foregroundView: foregroundView,
            shadowView: shadowView,
            liquidGlassView: liquidGlassView,
            maskContainerView: maskContainerView,
            maskContentView: maskContentView,
            contentContainer: contentContainer
        )
    }

    private func setupViewHierarchy() {
        if let shadowView = self.shadowView {
            self.addSubview(shadowView)
        }
        if let liquidGlassView = self.liquidGlassView {
            self.addSubview(liquidGlassView)
        }
        if let nativeParamsView = self.nativeParamsView {
            self.addSubview(nativeParamsView)
        }
        if let backgroundNode = self.backgroundNode {
            self.addSubview(backgroundNode.view)
        }
        if let foregroundView = self.foregroundView {
            self.addSubview(foregroundView)
            foregroundView.mask = self.maskContainerView
        }
        self.addSubview(self.contentContainer)
    }

    private func findChatControllerNodeView() -> UIView? {
        var current = self.superview
        while let view = current {
            if String(describing: type(of: view)) == "ChatControllerNodeView" {
                return view
            }
            current = view.superview
        }
        return nil
    }

    private func findListViewBackingView(in rootView: UIView) -> UIView? {
        var queue: [UIView] = [rootView]

        while !queue.isEmpty {
            let view = queue.removeFirst()

            if String(describing: type(of: view)) == "ListViewBackingView" {
                return view.superview?.superview
            }

            queue.append(contentsOf: view.subviews)
        }

        return nil
    }

    private func findViewByClassName(_ className: String, in rootView: UIView) -> UIView? {
        var queue: [UIView] = [rootView]

        while !queue.isEmpty {
            let view = queue.removeFirst()

            if String(describing: type(of: view)) == className {
                return view
            }

            queue.append(contentsOf: view.subviews)
        }

        return nil
    }

    private func configureSourceView(for liquidGlassView: LiquidGlassView) {
        guard liquidGlassView.sourceView == nil, let mode = self.mode else {
            return
        }

        switch mode {
        case .chat:
            if let chatControllerNodeView = self.findChatControllerNodeView() {
                if let listViewBackingViewParent = self.findListViewBackingView(in: chatControllerNodeView) {
                    liquidGlassView.sourceView = listViewBackingViewParent
                    liquidGlassView.continuousUpdate = true
                } else {
                    liquidGlassView.sourceView = self.superview
                }
            }
        case .chatList:
            if let window = self.window {
                if let tracingLayerView = self.findViewByClassName("UITracingLayerView", in: window) {
                    liquidGlassView.sourceView = tracingLayerView
                    liquidGlassView.continuousUpdate = true
                }
            }
        }
    }

    public func setSourceView(_ view: UIView?) {
        guard let liquidGlassView = self.liquidGlassView else {
            return
        }
        liquidGlassView.sourceView = view
        if view != nil {
            liquidGlassView.continuousUpdate = true
        }
    }

    public override init(frame: CGRect) {
        let components = GlassBackgroundView.prepareComponents(mode: nil)

        self.backgroundNode = components.backgroundNode
        self.nativeView = components.nativeView
        self.nativeViewClippingContext = components.nativeViewClippingContext
        self.nativeParamsView = components.nativeParamsView
        self.foregroundView = components.foregroundView
        self.shadowView = components.shadowView
        self.liquidGlassView = components.liquidGlassView
        self.maskContainerView = components.maskContainerView
        self.maskContentView = components.maskContentView
        self.contentContainer = components.contentContainer
        self.mode = nil

        super.init(frame: frame)

        self.setupViewHierarchy()
    }

    public init(frame: CGRect, mode: Mode) {
        let components = GlassBackgroundView.prepareComponents(mode: mode)

        self.backgroundNode = components.backgroundNode
        self.nativeView = components.nativeView
        self.nativeViewClippingContext = components.nativeViewClippingContext
        self.nativeParamsView = components.nativeParamsView
        self.foregroundView = components.foregroundView
        self.shadowView = components.shadowView
        self.liquidGlassView = components.liquidGlassView
        self.maskContainerView = components.maskContainerView
        self.maskContentView = components.maskContentView
        self.contentContainer = components.contentContainer
        self.mode = mode

        super.init(frame: frame)

        self.setupViewHierarchy()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let nativeView = self.nativeView {
            if let result = nativeView.hitTest(self.convert(point, to: nativeView), with: event) {
                return result
            }
        } else {
            if let result = self.contentContainer.hitTest(self.convert(point, to: self.contentContainer), with: event) {
                return result
            }
        }
        return nil
    }
        
    public func update(size: CGSize, cornerRadius: CGFloat, isDark: Bool, tintColor: TintColor, isInteractive: Bool = false, transition: ComponentTransition) {
        self.update(size: size, shape: .roundedRect(cornerRadius: cornerRadius), isDark: isDark, tintColor: tintColor, isInteractive: isInteractive, transition: transition)
    }
    
    public func update(size: CGSize, shape: Shape, isDark: Bool, tintColor: TintColor, isInteractive: Bool = false, transition: ComponentTransition) {
        if let nativeView = self.nativeView, let nativeViewClippingContext = self.nativeViewClippingContext, (nativeView.bounds.size != size || nativeViewClippingContext.shape != shape) {

            nativeViewClippingContext.update(shape: shape, size: size, transition: transition)
            if transition.animation.isImmediate {
                nativeView.frame = CGRect(origin: CGPoint(), size: size)
            } else {
                let nativeFrame = CGRect(origin: CGPoint(), size: size)
                transition.setFrame(view: nativeView, frame: nativeFrame)
            }
        }

        if let liquidGlassView = self.liquidGlassView {
            self.configureSourceView(for: liquidGlassView)

            let cornerRadius: CGFloat
            switch shape {
            case let .roundedRect(radius):
                cornerRadius = radius
            }

            var config = liquidGlassView.configuration
            config.cornerRadius = cornerRadius
            config.tint = tintColor.color.withAlphaComponent(1.0)

            liquidGlassView.configuration = config

            let frame = CGRect(origin: CGPoint(), size: size)
            if transition.animation.isImmediate {
                liquidGlassView.frame = frame
            } else {
                transition.setFrame(view: liquidGlassView, frame: frame)
            }

            liquidGlassView.isHidden = false

            liquidGlassView.invalidateBackground()
        }

        if let backgroundNode = self.backgroundNode {
            backgroundNode.updateColor(color: .clear, forceKeepBlur: tintColor.color.alpha != 1.0, transition: transition.containedViewLayoutTransition)
            
            switch shape {
            case let .roundedRect(cornerRadius):
                backgroundNode.update(size: size, cornerRadius: cornerRadius, transition: transition.containedViewLayoutTransition)
            }
            transition.setFrame(view: backgroundNode.view, frame: CGRect(origin: CGPoint(), size: size))
        }
        
        let shadowInset: CGFloat = 32.0

        if self.liquidGlassView == nil {
            if let innerColor = tintColor.innerColor {
                let innerBackgroundFrame = CGRect(origin: CGPoint(), size: size).insetBy(dx: 3.0, dy: 3.0)
                let innerBackgroundRadius = min(innerBackgroundFrame.width, innerBackgroundFrame.height) * 0.5

                let innerBackgroundView: UIView
                var innerBackgroundTransition = transition
                var animateIn = false
                if let current = self.innerBackgroundView {
                    innerBackgroundView = current
                } else {
                    innerBackgroundView = UIView()
                    innerBackgroundTransition = innerBackgroundTransition.withAnimation(.none)
                    self.innerBackgroundView = innerBackgroundView
                    self.contentView.insertSubview(innerBackgroundView, at: 0)

                    innerBackgroundView.frame = innerBackgroundFrame
                    innerBackgroundView.layer.cornerRadius = innerBackgroundRadius
                    animateIn = true
                }

                innerBackgroundView.backgroundColor = innerColor
                innerBackgroundTransition.setFrame(view: innerBackgroundView, frame: innerBackgroundFrame)
                innerBackgroundTransition.setCornerRadius(layer: innerBackgroundView.layer, cornerRadius: innerBackgroundRadius)

                if animateIn {
                    transition.animateAlpha(view: innerBackgroundView, from: 0.0, to: 1.0)
                    transition.animateScale(view: innerBackgroundView, from: 0.001, to: 1.0)
                }
            } else if let innerBackgroundView = self.innerBackgroundView {
                self.innerBackgroundView = nil

                transition.setAlpha(view: innerBackgroundView, alpha: 0.0, completion: { [weak innerBackgroundView] _ in
                    innerBackgroundView?.removeFromSuperview()
                })
                transition.setScale(view: innerBackgroundView, scale: 0.001)

                innerBackgroundView.removeFromSuperview()
            }
        }
        
        let params = Params(shape: shape, isDark: isDark, tintColor: tintColor, isInteractive: isInteractive)
        if self.params != params {
            self.params = params
            
            let outerCornerRadius: CGFloat
            switch shape {
            case let .roundedRect(cornerRadius):
                outerCornerRadius = cornerRadius
            }
            
            if let shadowView = self.shadowView {
                let shadowInnerInset: CGFloat = 0.5
                shadowView.image = generateImage(CGSize(width: shadowInset * 2.0 + outerCornerRadius * 2.0, height: shadowInset * 2.0 + outerCornerRadius * 2.0), rotatedContext: { size, context in
                    context.clear(CGRect(origin: CGPoint(), size: size))
                    
                    context.setFillColor(UIColor.black.cgColor)
                    context.setShadow(offset: CGSize(width: 0.0, height: 1.0), blur: 40.0, color: UIColor(white: 0.0, alpha: 0.04).cgColor)
                    context.fillEllipse(in: CGRect(origin: CGPoint(x: shadowInset + shadowInnerInset, y: shadowInset + shadowInnerInset), size: CGSize(width: size.width - shadowInset * 2.0 - shadowInnerInset * 2.0, height: size.height - shadowInset * 2.0 - shadowInnerInset * 2.0)))
                    
                    context.setFillColor(UIColor.clear.cgColor)
                    context.setBlendMode(.copy)
                    context.fillEllipse(in: CGRect(origin: CGPoint(x: shadowInset + shadowInnerInset, y: shadowInset + shadowInnerInset), size: CGSize(width: size.width - shadowInset * 2.0 - shadowInnerInset * 2.0, height: size.height - shadowInset * 2.0 - shadowInnerInset * 2.0)))
                })?.stretchableImage(withLeftCapWidth: Int(shadowInset + outerCornerRadius), topCapHeight: Int(shadowInset + outerCornerRadius))
            }
            
            if let foregroundView = self.foregroundView {
                foregroundView.image = GlassBackgroundView.generateLegacyGlassImage(size: CGSize(width: outerCornerRadius * 2.0, height: outerCornerRadius * 2.0), inset: shadowInset, isDark: isDark, fillColor: tintColor.color)
            } else {
                if let nativeParamsView = self.nativeParamsView, let nativeView = self.nativeView {
                    if #available(iOS 26.0, *) {
                        let glassEffect = UIGlassEffect(style: .regular)
                        switch tintColor.kind {
                        case .panel:
                            glassEffect.tintColor = UIColor(white: isDark ? 0.0 : 1.0, alpha: 0.1)
                        case .custom:
                            glassEffect.tintColor = tintColor.color
                        }
                        glassEffect.isInteractive = params.isInteractive
                        
                        if transition.animation.isImmediate {
                            nativeView.effect = glassEffect
                        } else {
                            UIView.animate(withDuration: 0.2, animations: {
                                nativeView.effect = glassEffect
                            })
                        }
                        
                        if isDark {
                            nativeParamsView.lumaMin = 0.0
                            nativeParamsView.lumaMax = 0.15
                        } else {
                            nativeParamsView.lumaMin = 0.6
                            nativeParamsView.lumaMax = 0.61
                        }
                    }
                }
            }
        }
        
        transition.setFrame(view: self.maskContainerView, frame: CGRect(origin: CGPoint(), size: CGSize(width: size.width + shadowInset * 2.0, height: size.height + shadowInset * 2.0)))
        transition.setFrame(view: self.maskContentView, frame: CGRect(origin: CGPoint(x: shadowInset, y: shadowInset), size: size))
        if let foregroundView = self.foregroundView {
            transition.setFrame(view: foregroundView, frame: CGRect(origin: CGPoint(), size: size).insetBy(dx: -shadowInset, dy: -shadowInset))
        }
        if let shadowView = self.shadowView {
            transition.setFrame(view: shadowView, frame: CGRect(origin: CGPoint(), size: size).insetBy(dx: -shadowInset, dy: -shadowInset))
        }
        transition.setFrame(view: self.contentContainer, frame: CGRect(origin: CGPoint(), size: size))
    }
}

// MARK: - Touch Tracking Gesture Recognizer

private final class TouchTrackingGestureRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onTouchBegan: ((CGPoint) -> Void)?
    var onTouchMoved: ((CGPoint) -> Void)?
    var onTouchEnded: (() -> Void)?

    private(set) var initialPosition: CGPoint = .zero

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        self.cancelsTouchesInView = false
        self.delaysTouchesBegan = false
        self.delaysTouchesEnded = false
        self.delegate = self
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let view = self.view else { return }

        self.state = .began
        self.initialPosition = touch.location(in: view.superview)
        self.onTouchBegan?(self.initialPosition)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first, let view = self.view else { return }

        self.state = .changed
        let currentPosition = touch.location(in: view.superview)
        self.onTouchMoved?(currentPosition)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        self.state = .ended
        self.onTouchEnded?()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        self.state = .cancelled
        self.onTouchEnded?()
    }

    override func reset() {
        super.reset()
        self.initialPosition = .zero
    }
}

// MARK: - Legacy Glass Morphing Controller

private final class LegacyGlassMorphingController {
    private weak var targetView: UIView?
    private var gestureRecognizer: TouchTrackingGestureRecognizer?

    private var initialTouchPoint: CGPoint = .zero
    private var isAnimatingBack: Bool = false
    private var isTouching: Bool = false

    // Configuration
    private let maxStretchFactor: CGFloat = 0.3
    private let stretchDistance: CGFloat = 700.0
    private let compressionRatio: CGFloat = 0.24

    // Touch scale effect
    private let touchScaleFactor: CGFloat
    private let touchScaleAnimationDuration: CGFloat = 0.15
    private let isMorphEnabled: Bool

    init(targetView: UIView, touchScaleFactor: CGFloat, isMorphEnabled: Bool = false) {
        self.targetView = targetView
        self.touchScaleFactor = touchScaleFactor
        self.isMorphEnabled = isMorphEnabled
        self.setupGestureRecognizer()
    }

    deinit {
        self.detach()
    }

    private func setupGestureRecognizer() {
        let gesture = TouchTrackingGestureRecognizer(target: nil, action: nil)
        gesture.onTouchBegan = { [weak self] point in
            self?.handleTouchBegan(at: point)
        }
        gesture.onTouchMoved = { [weak self] point in
            self?.handleTouchMoved(to: point)
        }
        gesture.onTouchEnded = { [weak self] in
            self?.handleTouchEnded()
        }
        self.targetView?.addGestureRecognizer(gesture)
        self.gestureRecognizer = gesture
    }

    private func handleTouchBegan(at point: CGPoint) {
        guard let view = self.targetView else { return }

        if self.isAnimatingBack {
            view.layer.removeAllAnimations()
            self.isAnimatingBack = false
        }

        self.initialTouchPoint = point
        self.isTouching = true

        // Scale up animation on touch
        UIView.animate(
            withDuration: self.touchScaleAnimationDuration,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction],
            animations: {
                view.layer.transform = CATransform3DMakeScale(self.touchScaleFactor, self.touchScaleFactor, 1.0)
            }
        )
    }

    private func handleTouchMoved(to point: CGPoint) {
        guard let view = self.targetView else { return }

        // If morph disabled, just keep the touch scale
        guard self.isMorphEnabled else { return }

        let delta = CGPoint(
            x: point.x - self.initialTouchPoint.x,
            y: point.y - self.initialTouchPoint.y
        )

        let distance = sqrt(delta.x * delta.x + delta.y * delta.y)

        guard distance > 1.0 else {
            // Keep the touch scale when not dragging
            view.layer.transform = CATransform3DMakeScale(self.touchScaleFactor, self.touchScaleFactor, 1.0)
            self.setAnchorPointPreservingPosition(CGPoint(x: 0.5, y: 0.5), for: view)
            return
        }

        // Normalized direction of pull
        let dirX = delta.x / distance
        let dirY = delta.y / distance

        // Anchor point is opposite to pull direction
        let anchorX = 0.5 - dirX * 0.5
        let anchorY = 0.5 - dirY * 0.5
        let newAnchor = CGPoint(x: anchorX, y: anchorY)

        self.setAnchorPointPreservingPosition(newAnchor, for: view)

        // Calculate stretch based on distance
        let stretchAmount = min(distance / self.stretchDistance, 1.0) * self.maxStretchFactor

        // Stretch more in the direction of pull
        let absX = abs(dirX)
        let absY = abs(dirY)

        // Base scale + directional stretch with compression
        let stretchX = self.touchScaleFactor + stretchAmount * absX - stretchAmount * absY * self.compressionRatio
        let stretchY = self.touchScaleFactor + stretchAmount * absY - stretchAmount * absX * self.compressionRatio

        view.layer.transform = CATransform3DMakeScale(stretchX, stretchY, 1.0)
    }

    private func handleTouchEnded() {
        guard let view = self.targetView else { return }

        self.isTouching = false
        self.isAnimatingBack = true

        UIView.animate(
            withDuration: 0.6,
            delay: 0,
            usingSpringWithDamping: 0.5,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: {
                view.layer.transform = CATransform3DIdentity
            },
            completion: { [weak self] finished in
                guard let self = self, finished else { return }
                self.isAnimatingBack = false
                if let view = self.targetView {
                    self.setAnchorPointPreservingPosition(CGPoint(x: 0.5, y: 0.5), for: view)
                }
            }
        )
    }

    private func setAnchorPointPreservingPosition(_ newAnchor: CGPoint, for view: UIView) {
        let oldAnchor = view.layer.anchorPoint
        if oldAnchor == newAnchor { return }

        let bounds = view.bounds
        let oldPosition = view.layer.position

        let newPosition = CGPoint(
            x: oldPosition.x + (newAnchor.x - oldAnchor.x) * bounds.width,
            y: oldPosition.y + (newAnchor.y - oldAnchor.y) * bounds.height
        )

        view.layer.anchorPoint = newAnchor
        view.layer.position = newPosition
    }

    func detach() {
        if let gesture = self.gestureRecognizer, let view = gesture.view {
            view.removeGestureRecognizer(gesture)
        }
        self.gestureRecognizer = nil
        if let view = self.targetView {
            view.layer.removeAllAnimations()
            view.layer.transform = CATransform3DIdentity
            self.setAnchorPointPreservingPosition(CGPoint(x: 0.5, y: 0.5), for: view)
        }
    }
}

// MARK: - Glass Background Container View

public final class GlassBackgroundContainerView: UIView {
    private final class ContentView: UIView {
        fileprivate var morphingControllers: [UIView: LegacyGlassMorphingController] = [:]

        override func willRemoveSubview(_ subview: UIView) {
            super.willRemoveSubview(subview)
            if let controller = self.morphingControllers.removeValue(forKey: subview) {
                controller.detach()
            }
        }

        func setTouchScale(for view: UIView, scale: CGFloat, isMorphEnabled: Bool = false) {
            if let existingController = self.morphingControllers[view] {
                existingController.detach()
            }
            let controller = LegacyGlassMorphingController(targetView: view, touchScaleFactor: scale, isMorphEnabled: isMorphEnabled)
            self.morphingControllers[view] = controller
        }

        func removeTouchScale(for view: UIView) {
            if let controller = self.morphingControllers.removeValue(forKey: view) {
                controller.detach()
            }
        }
    }
    
    private let legacyView: ContentView?
    private let nativeParamsView: EffectSettingsContainerView?
    private let nativeView: UIVisualEffectView?
    
    public var contentView: UIView {
        if let nativeView = self.nativeView {
            return nativeView.contentView
        } else {
            return self.legacyView!
        }
    }

    public func setTouchScale(to view: UIView, scale: CGFloat, isMorphEnabled: Bool = false) {
        self.legacyView?.setTouchScale(for: view, scale: scale, isMorphEnabled: isMorphEnabled)
    }

    public func removeTouchScale(from view: UIView) {
        self.legacyView?.removeTouchScale(for: view)
    }

    public override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = 7.0
            let nativeView = UIVisualEffectView(effect: effect)
            self.nativeView = nativeView
            
            let nativeParamsView = EffectSettingsContainerView(frame: CGRect())
            self.nativeParamsView = nativeParamsView
            nativeParamsView.addSubview(nativeView)
            
            self.legacyView = nil
        } else {
            self.nativeView = nil
            self.nativeParamsView = nil
            self.legacyView = ContentView()
        }
        
        super.init(frame: frame)
        
        if let nativeParamsView = self.nativeParamsView {
            self.addSubview(nativeParamsView)
        } else if let legacyView = self.legacyView {
            self.addSubview(legacyView)
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override public func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        
        if subview !== self.nativeParamsView && subview !== self.legacyView {
            assertionFailure()
        }
    }
    
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let result = self.contentView.hitTest(point, with: event) else {
            return nil
        }
        return result
    }
    
    public func update(size: CGSize, isDark: Bool, transition: ComponentTransition) {
        if let nativeParamsView = self.nativeParamsView, let nativeView = self.nativeView {
            nativeView.overrideUserInterfaceStyle = isDark ? .dark : .light
            
            if isDark {
                nativeParamsView.lumaMin = 0.0
                nativeParamsView.lumaMax = 0.15
            } else {
                nativeParamsView.lumaMin = 0.6
                nativeParamsView.lumaMax = 0.61
            }
            
            transition.setFrame(view: nativeView, frame: CGRect(origin: CGPoint(), size: size))
        } else if let legacyView = self.legacyView {
            transition.setFrame(view: legacyView, frame: CGRect(origin: CGPoint(), size: size))
        }
    }
}

private extension CGContext {
    func addBadgePath(in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.minY)
        scaleBy(x: rect.width / 78.0, y: rect.height / 78.0)
        
        // M 0 39
        move(to: CGPoint(x: 0, y: 39))
        
        // C 0 17.4609 17.4609 0 39 0
        addCurve(to: CGPoint(x: 39, y: 0),
                 control1: CGPoint(x: 0,       y: 17.4609),
                 control2: CGPoint(x: 17.4609, y: 0))
        
        // H 42
        addLine(to: CGPoint(x: 42, y: 0))
        
        // C 61.8823 0 78 16.1177 78 36
        addCurve(to: CGPoint(x: 78, y: 36),
                 control1: CGPoint(x: 61.8823, y: 0),
                 control2: CGPoint(x: 78,      y: 16.1177))
        
        // V 39
        addLine(to: CGPoint(x: 78, y: 39))
        
        // C 78 60.5391 60.5391 78 39 78
        addCurve(to: CGPoint(x: 39, y: 78),
                 control1: CGPoint(x: 78,      y: 60.5391),
                 control2: CGPoint(x: 60.5391, y: 78))
        
        // H 36
        addLine(to: CGPoint(x: 36, y: 78))
        
        // C 16.1177 78 0 61.8823 0 42
        addCurve(to: CGPoint(x: 0, y: 42),
                 control1: CGPoint(x: 16.1177, y: 78),
                 control2: CGPoint(x: 0,       y: 61.8823))
        
        // V 39 / Z
        addLine(to: CGPoint(x: 0, y: 39))
        closePath()
        
        restoreGState()
    }
}

public extension GlassBackgroundView {
    static func generateLegacyGlassImage(size: CGSize, inset: CGFloat, isDark: Bool, fillColor: UIColor) -> UIImage {
        var size = size
        if size == .zero {
            size = CGSize(width: 2.0, height: 2.0)
        }
        let innerSize = size
        size.width += inset * 2.0
        size.height += inset * 2.0
        
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let context = ctx.cgContext
            
            context.clear(CGRect(origin: CGPoint(), size: size))

            let addShadow: (CGContext, Bool, CGPoint, CGFloat, CGFloat, UIColor, CGBlendMode) -> Void = { context, isOuter, position, blur, spread, shadowColor, blendMode in
                var blur = blur
                
                if isOuter {
                    blur += abs(spread)
                    
                    context.beginTransparencyLayer(auxiliaryInfo: nil)
                    context.saveGState()
                    defer {
                        context.restoreGState()
                        context.endTransparencyLayer()
                    }

                    let spreadRect = CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize).insetBy(dx: 0.25, dy: 0.25)
                    let spreadPath = UIBezierPath(
                        roundedRect: spreadRect,
                        cornerRadius: min(spreadRect.width, spreadRect.height) * 0.5
                    ).cgPath

                    context.setShadow(offset: CGSize(width: position.x, height: position.y), blur: blur, color: shadowColor.cgColor)
                    context.setFillColor(UIColor.black.withAlphaComponent(1.0).cgColor)
                    context.addPath(spreadPath)
                    context.fillPath()
                    
                    let cleanRect = CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize)
                    let cleanPath = UIBezierPath(
                        roundedRect: cleanRect,
                        cornerRadius: min(cleanRect.width, cleanRect.height) * 0.5
                    ).cgPath
                    context.setBlendMode(.copy)
                    context.setFillColor(UIColor.clear.cgColor)
                    context.addPath(cleanPath)
                    context.fillPath()
                    context.setBlendMode(.normal)
                } else {
                    let image = UIGraphicsImageRenderer(size: size).image(actions: { ctx in
                        let context = ctx.cgContext
                        
                        context.clear(CGRect(origin: CGPoint(), size: size))
                        let spreadRect = CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize).insetBy(dx: -spread - 0.33, dy: -spread - 0.33)

                        context.setShadow(offset: CGSize(width: position.x, height: position.y), blur: blur, color: shadowColor.cgColor)
                        context.setFillColor(shadowColor.cgColor)
                        let enclosingRect = spreadRect.insetBy(dx: -10000.0, dy: -10000.0)
                        context.addPath(UIBezierPath(rect: enclosingRect).cgPath)
                        context.addBadgePath(in: spreadRect)
                        context.fillPath(using: .evenOdd)
                    })
                    
                    UIGraphicsPushContext(context)
                    image.draw(in: CGRect(origin: .zero, size: size), blendMode: blendMode, alpha: 1.0)
                    UIGraphicsPopContext()
                }
            }
            
            addShadow(context, true, CGPoint(), 10.0, 0.0, UIColor(white: 0.0, alpha: 0.06), .normal)
            addShadow(context, true, CGPoint(), 20.0, 0.0, UIColor(white: 0.0, alpha: 0.06), .normal)
            
            var a: CGFloat = 0.0
            var b: CGFloat = 0.0
            var s: CGFloat = 0.0
            fillColor.getHue(nil, saturation: &s, brightness: &b, alpha: &a)
            
            let innerImage: UIImage
            if size == CGSize(width: 40.0 + inset * 2.0, height: 40.0 + inset * 2.0), b >= 0.2 {
                innerImage = UIGraphicsImageRenderer(size: size).image { ctx in
                    let context = ctx.cgContext
                    
                    context.setFillColor(fillColor.cgColor)
                    context.fill(CGRect(origin: CGPoint(), size: size))
                    
                    if let image = UIImage(bundleImageName: "Item List/GlassEdge40x40") {
                        let imageInset = (image.size.width - 40.0) * 0.5
                        
                        if s == 0.0 && abs(a - 0.7) < 0.1 && !isDark {
                            image.draw(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: inset - imageInset, dy: inset - imageInset), blendMode: .normal, alpha: 1.0)
                        } else if s <= 0.3 && !isDark {
                            image.draw(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: inset - imageInset, dy: inset - imageInset), blendMode: .normal, alpha: 0.7)
                        } else if b >= 0.2 {
                            let maxAlpha: CGFloat = isDark ? 0.7 : 0.8
                            image.draw(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: inset - imageInset, dy: inset - imageInset), blendMode: .overlay, alpha: max(0.5, min(1.0, maxAlpha * s)))
                        } else {
                            image.draw(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: inset - imageInset, dy: inset - imageInset), blendMode: .normal, alpha: 0.5)
                        }
                    }
                }
            } else {
                innerImage = UIGraphicsImageRenderer(size: size).image { ctx in
                    let context = ctx.cgContext
                    
                    context.setFillColor(fillColor.cgColor)
                    context.fill(CGRect(origin: CGPoint(), size: size).insetBy(dx: inset, dy: inset).insetBy(dx: 0.1, dy: 0.1))
                    
                    addShadow(context, true, CGPoint(x: 0.0, y: 0.0), 20.0, 0.0, UIColor(white: 0.0, alpha: 0.04), .normal)
                    addShadow(context, true, CGPoint(x: 0.0, y: 0.0), 5.0, 0.0, UIColor(white: 0.0, alpha: 0.04), .normal)
                    
                    if s <= 0.3 && !isDark {
                        addShadow(context, false, CGPoint(x: 0.0, y: 0.0), 8.0, 0.0, UIColor(white: 0.0, alpha: 0.4), .overlay)
                        
                        let edgeAlpha: CGFloat = max(0.8, min(1.0, a))
                        
                        for _ in 0 ..< 2 {
                            addShadow(context, false, CGPoint(x: -0.64, y: -0.64), 0.8, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .normal)
                            addShadow(context, false, CGPoint(x: 0.64, y: 0.64), 0.8, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .normal)
                        }
                    } else if b >= 0.2 {
                        let edgeAlpha: CGFloat = max(0.2, min(isDark ? 0.5 : 0.7, a * a * a))
                        
                        addShadow(context, false, CGPoint(x: -0.64, y: -0.64), 0.5, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .plusLighter)
                        addShadow(context, false, CGPoint(x: 0.64, y: 0.64), 0.5, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .plusLighter)
                    } else {
                        let edgeAlpha: CGFloat = max(0.4, min(isDark ? 0.5 : 0.7, a * a * a))
                        
                        addShadow(context, false, CGPoint(x: -0.64, y: -0.64), 1.2, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .normal)
                        addShadow(context, false, CGPoint(x: 0.64, y: 0.64), 1.2, 0.0, UIColor(white: 1.0, alpha: edgeAlpha), .normal)
                    }
                }
            }
            
            context.addEllipse(in: CGRect(origin: CGPoint(x: inset, y: inset), size: innerSize))
            context.clip()
            innerImage.draw(in: CGRect(origin: CGPoint(), size: size))
        }.stretchableImage(withLeftCapWidth: Int(size.width * 0.5), topCapHeight: Int(size.height * 0.5))
    }
    
    static func generateForegroundImage(size: CGSize, isDark: Bool, fillColor: UIColor) -> UIImage {
        var size = size
        if size == .zero {
            size = CGSize(width: 1.0, height: 1.0)
        }
        
        return generateImage(size, rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            
            let maxColor = UIColor(white: 1.0, alpha: isDark ? 0.2 : 0.9)
            let minColor = UIColor(white: 1.0, alpha: 0.0)
            
            context.setFillColor(fillColor.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
            
            let lineWidth: CGFloat = isDark ? 0.33 : 0.66
            
            context.saveGState()
            
            let darkShadeColor = UIColor(white: isDark ? 1.0 : 0.0, alpha: isDark ? 0.0 : 0.035)
            let lightShadeColor = UIColor(white: isDark ? 0.0 : 1.0, alpha: isDark ? 0.0 : 0.035)
            let innerShadowBlur: CGFloat = 24.0
            
            context.resetClip()
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5))
            context.clip()
            context.addRect(CGRect(origin: CGPoint(), size: size).insetBy(dx: -100.0, dy: -100.0))
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size))
            context.setFillColor(UIColor.black.cgColor)
            context.setShadow(offset: CGSize(width: 10.0, height: -10.0), blur: innerShadowBlur, color: darkShadeColor.cgColor)
            context.fillPath(using: .evenOdd)
            
            context.resetClip()
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5))
            context.clip()
            context.addRect(CGRect(origin: CGPoint(), size: size).insetBy(dx: -100.0, dy: -100.0))
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size))
            context.setFillColor(UIColor.black.cgColor)
            context.setShadow(offset: CGSize(width: -10.0, height: 10.0), blur: innerShadowBlur, color: lightShadeColor.cgColor)
            context.fillPath(using: .evenOdd)
            
            context.restoreGState()
            
            context.setLineWidth(lineWidth)
            
            context.addRect(CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: size.width * 0.5, height: size.height)))
            context.clip()
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5))
            context.replacePathWithStrokedPath()
            context.clip()
            
            do {
                var locations: [CGFloat] = [0.0, 0.5, 0.5 + 0.2, 1.0 - 0.1, 1.0]
                let colors: [CGColor] = [maxColor.cgColor, maxColor.cgColor, minColor.cgColor, minColor.cgColor, maxColor.cgColor]
                
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
                
                context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())
            }
            
            context.resetClip()
            context.addRect(CGRect(origin: CGPoint(x: size.width - size.width * 0.5, y: 0.0), size: CGSize(width: size.width * 0.5, height: size.height)))
            context.clip()
            context.addEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5))
            context.replacePathWithStrokedPath()
            context.clip()
            
            do {
                var locations: [CGFloat] = [0.0, 0.1, 0.5 - 0.2, 0.5, 1.0]
                let colors: [CGColor] = [maxColor.cgColor, minColor.cgColor, minColor.cgColor, maxColor.cgColor, maxColor.cgColor]
                
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
                
                context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())
            }
        })!.stretchableImage(withLeftCapWidth: Int(size.width * 0.5), topCapHeight: Int(size.height * 0.5))
    }
}

public final class GlassBackgroundComponent: Component {
    private let size: CGSize
    private let cornerRadius: CGFloat
    private let isDark: Bool
    private let tintColor: GlassBackgroundView.TintColor
    
    public init(size: CGSize, cornerRadius: CGFloat, isDark: Bool, tintColor: GlassBackgroundView.TintColor) {
        self.size = size
        self.cornerRadius = cornerRadius
        self.isDark = isDark
        self.tintColor = tintColor
    }
    
    public static func == (lhs: GlassBackgroundComponent, rhs: GlassBackgroundComponent) -> Bool {
        if lhs.size != rhs.size {
            return false
        }
        if lhs.cornerRadius != rhs.cornerRadius {
            return false
        }
        if lhs.isDark != rhs.isDark {
            return false
        }
        if lhs.tintColor != rhs.tintColor {
            return false
        }
        return true
    }
    
    public final class View: GlassBackgroundView {
        func update(component: GlassBackgroundComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.update(size: component.size, cornerRadius: component.cornerRadius, isDark: component.isDark, tintColor: component.tintColor, transition: transition)
            
            return component.size
        }
    }
    
    public func makeView() -> View {
        return View()
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
