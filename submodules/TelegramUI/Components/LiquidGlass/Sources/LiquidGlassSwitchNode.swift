import Foundation
import UIKit
import AsyncDisplayKit
import Display

private enum SwitchConstants {
    static let width: CGFloat = 63.0
    static let height: CGFloat = 28.0
    static let thumbWidth: CGFloat = 39.0
    static let thumbHeight: CGFloat = 24.0
    static let padding: CGFloat = 2.0
    static let trackCornerRadius: CGFloat = 14.0
    static let thumbCornerRadius: CGFloat = 12.0
    static let animationDuration: TimeInterval = 0.25

    static let liquidGlassWidth: CGFloat = 54.0
    static let liquidGlassHeight: CGFloat = height + 8.0
    static var liquidGlassCornerRadius: CGFloat { SwitchConstants.liquidGlassHeight / 2.0 }
    static let liquidGlassAnimationDuration: TimeInterval = 0.2
    static let liquidGlassCapturePadding: CGPoint = CGPoint(x: 8.0, y: 8.0)
    static let liquidGlassEdgeWidthMultiplier: CGFloat = 1.04

    static let glassTrackHeight: CGFloat = height
    static var glassTrackCornerRadius: CGFloat { glassTrackHeight / 2.0 }
}

private final class LiquidGlassSwitchNodeViewLayer: CALayer {
    override func setNeedsDisplay() {
    }
}

private final class LiquidGlassSwitchNodeView: UISwitch {
    override class var layerClass: AnyClass {
        if #available(iOS 26.0, *) {
            return super.layerClass
        } else {
            return LiquidGlassSwitchNodeViewLayer.self
        }
    }
}

private final class LiquidGlassCustomSwitchViewLayer: CALayer {
    override func setNeedsDisplay() {
    }
}

private final class LiquidGlassCustomSwitchView: UIView {

    override class var layerClass: AnyClass {
        return LiquidGlassCustomSwitchViewLayer.self
    }

    var valueChanged: ((Bool) -> Void)?

    private let contentView = UIView()
    private let trackLayer = SimpleLayer()
    private let thumbLayer = SimpleLayer()

    private var _isOn: Bool = false
    var isOn: Bool {
        get { return _isOn }
        set {
            if _isOn != newValue {
                _isOn = newValue
                visuallyOn = newValue
                updateThumbPosition(animated: false)
                updateTrackColor(animated: false)
            }
        }
    }

    var onTintColor: UIColor = UIColor(rgb: 0x42d451) {
        didSet {
            if _isOn {
                updateTrackColor(animated: false)
            }
        }
    }

    var offTintColor: UIColor = UIColor(rgb: 0xe0e0e0) {
        didSet {
            if !_isOn {
                updateTrackColor(animated: false)
            }
        }
    }

    var thumbTintColor: UIColor = .white {
        didSet {
            thumbLayer.backgroundColor = thumbTintColor.cgColor
        }
    }

    private var panStartThumbX: CGFloat = 0
    private var isPanning: Bool = false

    private var visuallyOn: Bool = false

    private var liquidGlassView: LiquidGlassView?
    private var liquidGlassMorphAnimator: LiquidGlassMorphAnimator?

    private var lastPanPosition: CGPoint = .zero
    private var lastPanTime: CFTimeInterval = 0
    private var currentVelocity: CGPoint = .zero

    private var thumbPositionAnimationLink: SharedDisplayLinkDriver.Link?

    private var contentMaskLayer: CAShapeLayer?

    private var glassTrackView: UIView?
    private var glassTrackMaskLayer: CAShapeLayer?

    private let hapticFeedback = HapticFeedback()

    private var thumbMinX: CGFloat {
        return SwitchConstants.padding
    }

    private var thumbMaxX: CGFloat {
        return bounds.width - SwitchConstants.thumbWidth - SwitchConstants.padding
    }

    private var thumbOffX: CGFloat {
        return thumbMinX
    }

    private var thumbOnX: CGFloat {
        return thumbMaxX
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupGestures()
    }

    private func setupLayers() {
        contentView.isUserInteractionEnabled = false
        addSubview(contentView)

        trackLayer.backgroundColor = offTintColor.cgColor
        trackLayer.cornerRadius = SwitchConstants.trackCornerRadius
        contentView.layer.addSublayer(trackLayer)

        thumbLayer.backgroundColor = thumbTintColor.cgColor
        thumbLayer.cornerRadius = SwitchConstants.thumbCornerRadius
        thumbLayer.shadowColor = UIColor.black.cgColor
        thumbLayer.shadowOffset = CGSize(width: 0, height: 2)
        thumbLayer.shadowOpacity = 0.2
        thumbLayer.shadowRadius = 4
        contentView.layer.addSublayer(thumbLayer)
    }

    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)

        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)

        self.interactiveTransitionGestureRecognizerTest = { [weak self] point in
            guard let self = self else { return false }
            return self.bounds.contains(point)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard bounds.width > 0 && bounds.height > 0 else { return }

        contentView.frame = bounds
        trackLayer.frame = bounds

        let thumbY = (bounds.height - SwitchConstants.thumbHeight) / 2.0
        let thumbX = _isOn ? thumbOnX : thumbOffX
        thumbLayer.frame = CGRect(x: thumbX, y: thumbY, width: SwitchConstants.thumbWidth, height: SwitchConstants.thumbHeight)
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: SwitchConstants.width, height: SwitchConstants.height)
    }

    func setOn(_ on: Bool, animated: Bool) {
        guard _isOn != on else { return }
        _isOn = on
        visuallyOn = on
        updateThumbPosition(animated: animated)
        updateTrackColor(animated: animated)
    }

    private func updateThumbPosition(animated: Bool) {
        guard bounds.width > 0 && bounds.height > 0 else { return }

        let targetX = _isOn ? thumbOnX : thumbOffX
        let thumbY = (bounds.height - SwitchConstants.thumbHeight) / 2.0
        let newFrame = CGRect(x: targetX, y: thumbY, width: SwitchConstants.thumbWidth, height: SwitchConstants.thumbHeight)

        if animated {
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = thumbLayer.position
            animation.toValue = CGPoint(x: newFrame.midX, y: newFrame.midY)
            animation.duration = SwitchConstants.animationDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .backwards
            thumbLayer.add(animation, forKey: "position")
        }

        thumbLayer.frame = newFrame
    }

    private func updateTrackColor(animated: Bool) {
        let targetColor = visuallyOn ? onTintColor.cgColor : offTintColor.cgColor

        if animated {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = trackLayer.backgroundColor
            animation.toValue = targetColor
            animation.duration = SwitchConstants.animationDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .backwards
            trackLayer.add(animation, forKey: "backgroundColor")
        }

        trackLayer.backgroundColor = targetColor

        updateGlassTrackColor(animated: animated)
    }

    private func setThumbX(_ x: CGFloat, animated: Bool = false) {
        guard bounds.width > 0 && bounds.height > 0 else { return }

        let clampedX = max(thumbMinX, min(thumbMaxX, x))
        let thumbY = (bounds.height - SwitchConstants.thumbHeight) / 2.0
        let newFrame = CGRect(x: clampedX, y: thumbY, width: SwitchConstants.thumbWidth, height: SwitchConstants.thumbHeight)

        if animated {
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = thumbLayer.position
            animation.toValue = CGPoint(x: newFrame.midX, y: newFrame.midY)
            animation.duration = SwitchConstants.animationDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.fillMode = .backwards
            thumbLayer.add(animation, forKey: "position")
        }

        thumbLayer.frame = newFrame

        if clampedX <= thumbMinX && visuallyOn {
            visuallyOn = false
            updateTrackColor(animated: true)
            hapticFeedback.impact(.light)
        } else if clampedX >= thumbMaxX && !visuallyOn {
            visuallyOn = true
            updateTrackColor(animated: true)
            hapticFeedback.impact(.light)
        }
    }

    private func updateTrackColorForProgress(_ progress: CGFloat) {
        let offColor = offTintColor
        let onColor = onTintColor

        var offRed: CGFloat = 0, offGreen: CGFloat = 0, offBlue: CGFloat = 0, offAlpha: CGFloat = 0
        var onRed: CGFloat = 0, onGreen: CGFloat = 0, onBlue: CGFloat = 0, onAlpha: CGFloat = 0

        offColor.getRed(&offRed, green: &offGreen, blue: &offBlue, alpha: &offAlpha)
        onColor.getRed(&onRed, green: &onGreen, blue: &onBlue, alpha: &onAlpha)

        let red = offRed + (onRed - offRed) * progress
        let green = offGreen + (onGreen - offGreen) * progress
        let blue = offBlue + (onBlue - offBlue) * progress
        let alpha = offAlpha + (onAlpha - offAlpha) * progress

        trackLayer.backgroundColor = UIColor(red: red, green: green, blue: blue, alpha: alpha).cgColor
    }

    private func liquidGlassWidthMultiplier(for thumbX: CGFloat) -> CGFloat {
        guard thumbMaxX > thumbMinX else { return 1.0 }
        let centerX = (thumbMinX + thumbMaxX) / 2.0
        let maxDistance = (thumbMaxX - thumbMinX) / 2.0
        let normalizedDistance = abs(thumbX - centerX) / maxDistance
        return 1.0 + (SwitchConstants.liquidGlassEdgeWidthMultiplier - 1.0) * normalizedDistance
    }

    private func liquidGlassFrame(for thumbFrame: CGRect) -> CGRect {
        let widthMultiplier = liquidGlassWidthMultiplier(for: thumbFrame.origin.x)
        let dynamicWidth = SwitchConstants.liquidGlassWidth * widthMultiplier
        return CGRect(
            x: thumbFrame.midX - dynamicWidth / 2,
            y: thumbFrame.midY - SwitchConstants.liquidGlassHeight / 2,
            width: dynamicWidth,
            height: SwitchConstants.liquidGlassHeight
        )
    }

    private func updateContentMask(cutoutFrame: CGRect?, cornerRadius: CGFloat) {
        guard let cutoutFrame = cutoutFrame else {
            trackLayer.mask = nil
            contentMaskLayer = nil
            return
        }

        let maskLayer: CAShapeLayer
        if let existing = contentMaskLayer {
            maskLayer = existing
        } else {
            maskLayer = CAShapeLayer()
            maskLayer.fillRule = .evenOdd
            maskLayer.fillColor = UIColor.black.cgColor
            contentMaskLayer = maskLayer
            trackLayer.mask = maskLayer
        }

        let path = UIBezierPath(rect: contentView.bounds)
        let cutoutPath = UIBezierPath(roundedRect: cutoutFrame, cornerRadius: cornerRadius)
        path.append(cutoutPath)

        maskLayer.path = path.cgPath
    }

    private func setupGlassTrackIfNeeded() {
        guard self.glassTrackView == nil else { return }

        let glassTrackView = UIView()
        glassTrackView.backgroundColor = visuallyOn ? onTintColor : offTintColor
        glassTrackView.layer.cornerRadius = SwitchConstants.glassTrackCornerRadius
        glassTrackView.isHidden = true
        glassTrackView.isUserInteractionEnabled = false

        contentView.addSubview(glassTrackView)
        contentView.sendSubviewToBack(glassTrackView)

        self.glassTrackView = glassTrackView
    }

    private func updateGlassTrackFrame() {
        guard let glassTrackView = self.glassTrackView else { return }

        let trackHeight = SwitchConstants.glassTrackHeight
        let trackFrame = CGRect(
            x: -SwitchConstants.liquidGlassCapturePadding.x / 2.0,
            y: (contentView.bounds.height - trackHeight) / 2.0,
            width: contentView.bounds.width + SwitchConstants.liquidGlassCapturePadding.x,
            height: trackHeight
        )
        glassTrackView.frame = trackFrame
    }

    private func updateGlassTrackMask(visibleFrame: CGRect?, cornerRadius: CGFloat) {
        guard let glassTrackView = self.glassTrackView else { return }

        guard let visibleFrame = visibleFrame else {
            glassTrackView.layer.mask = nil
            glassTrackMaskLayer = nil
            glassTrackView.isHidden = true
            return
        }

        glassTrackView.isHidden = false

        let maskLayer: CAShapeLayer
        if let existing = glassTrackMaskLayer {
            maskLayer = existing
        } else {
            maskLayer = CAShapeLayer()
            maskLayer.fillColor = UIColor.black.cgColor
            glassTrackMaskLayer = maskLayer
            glassTrackView.layer.mask = maskLayer
        }

        let localFrame = glassTrackView.convert(visibleFrame, from: self)

        let path = UIBezierPath(roundedRect: localFrame, cornerRadius: cornerRadius)
        maskLayer.path = path.cgPath
    }

    private func updateGlassTrackColor(animated: Bool) {
        guard let trackView = self.glassTrackView else { return }

        let targetColor = visuallyOn ? onTintColor : offTintColor

        if animated {
            UIView.animate(withDuration: SwitchConstants.animationDuration) {
                trackView.backgroundColor = targetColor
            }
        } else {
            trackView.backgroundColor = targetColor
        }
    }

    private var liquidGlassContainer: UIView? {
        return superview?.superview
    }

    private var liquidGlassSourceView: UIView? {
        return superview
    }

    private func convertToLiquidGlassContainer(_ frame: CGRect) -> CGRect {
        guard let container = liquidGlassContainer else { return frame }
        return self.convert(frame, to: container)
    }

    private func setupLiquidGlassIfNeeded() {
        guard self.liquidGlassView == nil else { return }
        guard let container = liquidGlassContainer,
              let sourceView = liquidGlassSourceView else { return }

        var config = LiquidGlassConfiguration()
        config.refThickness = 8
        config.shapePadding = CGPoint(x: 10, y: 10)
        config.capturePadding = SwitchConstants.liquidGlassCapturePadding
        config.cornerRadius = SwitchConstants.liquidGlassCornerRadius
        let glass = LiquidGlassView(configuration: config)
        glass.sourceView = sourceView
        glass.isHidden = true
        container.addSubview(glass)
        self.liquidGlassView = glass

        let morphAnimator = LiquidGlassMorphAnimator()
        morphAnimator.onMorphScaleChanged = { [weak glass] scale in
            glass?.setMorphScale(scale)
        }
        self.liquidGlassMorphAnimator = morphAnimator
    }

    private func performCleanup(
        glass: LiquidGlassView,
        morphAnimator: LiquidGlassMorphAnimator?,
        glassTrackView: UIView?,
        glassTrackMaskLayer: CAShapeLayer?,
        contentMaskLayer: CAShapeLayer?
    ) {
        morphAnimator?.forceStop()

        glass.layer.transform = CATransform3DIdentity
        glass.pauseRendering()
        glass.removeFromSuperview()

        if self.trackLayer.mask === contentMaskLayer {
            self.trackLayer.mask = nil
        }

        if let trackView = glassTrackView {
            trackView.layer.mask = nil
            trackView.removeFromSuperview()
        }
    }


    private func showLiquidGlass() {
        setupLiquidGlassIfNeeded()
        guard let glass = self.liquidGlassView else { return }

        setupGlassTrackIfNeeded()
        updateGlassTrackFrame()

        let thumbFrameLocal = self.thumbLayer.frame

        let targetFrameLocal = liquidGlassFrame(for: thumbFrameLocal)
        let targetFrameInContainer = convertToLiquidGlassContainer(targetFrameLocal)

        glass.frame = targetFrameInContainer
        glass.configuration.cornerRadius = SwitchConstants.liquidGlassCornerRadius

        let scaleX = thumbFrameLocal.width / targetFrameLocal.width
        let scaleY = thumbFrameLocal.height / targetFrameLocal.height
        glass.layer.transform = CATransform3DMakeScale(scaleX, scaleY, 1.0)

        glass.alpha = 0
        glass.isHidden = false

        updateContentMask(cutoutFrame: thumbFrameLocal, cornerRadius: thumbFrameLocal.height / 2.0)
        updateGlassTrackMask(visibleFrame: thumbFrameLocal, cornerRadius: thumbFrameLocal.height / 2.0)

        let transition = ContainedViewLayoutTransition.animated(
            duration: SwitchConstants.liquidGlassAnimationDuration,
            curve: .easeInOut
        )

        transition.updateTransformScale(layer: glass.layer, scale: CGPoint(x: 1.0, y: 1.0))
        transition.updateAlpha(layer: glass.layer, alpha: 1.0)

        transition.updateAlpha(layer: self.thumbLayer, alpha: 0.0)

        updateContentMask(cutoutFrame: targetFrameLocal, cornerRadius: SwitchConstants.liquidGlassCornerRadius)
        updateGlassTrackMask(visibleFrame: targetFrameLocal, cornerRadius: SwitchConstants.liquidGlassCornerRadius)

        self.liquidGlassMorphAnimator?.start()
    }

    private func hideLiquidGlass(toThumbFrame targetThumbFrameLocal: CGRect, animated: Bool, completion: (() -> Void)? = nil) {
        guard let glass = self.liquidGlassView else {
            completion?()
            return
        }
        let morphAnimator = self.liquidGlassMorphAnimator
        let glassTrackView = self.glassTrackView
        let glassTrackMaskLayer = self.glassTrackMaskLayer
        let contentMaskLayer = self.contentMaskLayer

        self.liquidGlassView = nil
        self.liquidGlassMorphAnimator = nil
        self.glassTrackView = nil
        self.glassTrackMaskLayer = nil
        self.contentMaskLayer = nil

        morphAnimator?.stop()

        let transition: ContainedViewLayoutTransition = animated
            ? .animated(duration: SwitchConstants.liquidGlassAnimationDuration, curve: .easeInOut)
            : .immediate

        let finalFrameLocal = liquidGlassFrame(for: targetThumbFrameLocal)
        let finalFrameInContainer = convertToLiquidGlassContainer(finalFrameLocal)
        transition.updateFrame(view: glass, frame: finalFrameInContainer)

        let scaleX = targetThumbFrameLocal.width / finalFrameLocal.width
        let scaleY = targetThumbFrameLocal.height / finalFrameLocal.height
        transition.updateTransformScale(layer: glass.layer, scale: CGPoint(x: scaleX, y: scaleY), completion: { [weak self] _ in
            self?.performCleanup(
                glass: glass,
                morphAnimator: morphAnimator,
                glassTrackView: glassTrackView,
                glassTrackMaskLayer: glassTrackMaskLayer,
                contentMaskLayer: contentMaskLayer
            )
            completion?()
        })
        transition.updateAlpha(layer: glass.layer, alpha: 0.0)

        if let glassTrackView = glassTrackView, let glassTrackMaskLayer = glassTrackMaskLayer {
            let localFrame = glassTrackView.convert(targetThumbFrameLocal, from: self)
            let path = UIBezierPath(roundedRect: localFrame, cornerRadius: targetThumbFrameLocal.height / 2.0)
            glassTrackMaskLayer.path = path.cgPath
        }

        if let contentMaskLayer = contentMaskLayer {
            let path = UIBezierPath(rect: contentView.bounds)
            let cutoutPath = UIBezierPath(roundedRect: targetThumbFrameLocal, cornerRadius: targetThumbFrameLocal.height / 2.0)
            path.append(cutoutPath)
            contentMaskLayer.path = path.cgPath
        }

        transition.updateAlpha(layer: self.thumbLayer, alpha: 1.0)
    }

    private func updateLiquidGlassFrame() {
        guard let glass = self.liquidGlassView else { return }

        let frameLocal = liquidGlassFrame(for: self.thumbLayer.frame)
        let frameInContainer = convertToLiquidGlassContainer(frameLocal)

        glass.frame = frameInContainer

        updateContentMask(cutoutFrame: frameLocal, cornerRadius: glass.configuration.cornerRadius)
        updateGlassTrackMask(visibleFrame: frameLocal, cornerRadius: glass.configuration.cornerRadius)
    }

    private func resetVelocityTracking(at point: CGPoint) {
        self.lastPanPosition = point
        self.lastPanTime = CACurrentMediaTime()
        self.currentVelocity = .zero
    }

    private func updateVelocity(at point: CGPoint) {
        let currentTime = CACurrentMediaTime()
        let dt = currentTime - self.lastPanTime

        if dt > 0.001 {
            self.currentVelocity = CGPoint(
                x: (point.x - self.lastPanPosition.x) / dt,
                y: (point.y - self.lastPanPosition.y) / dt
            )
        }

        self.lastPanPosition = point
        self.lastPanTime = currentTime
    }

    private func animateThumbToFinalPosition(completion: @escaping () -> Void) {
        guard bounds.width > 0 && bounds.height > 0 else {
            completion()
            return
        }

        self.thumbPositionAnimationLink?.invalidate()
        self.thumbPositionAnimationLink = nil

        let targetX = _isOn ? thumbOnX : thumbOffX
        let thumbY = (bounds.height - SwitchConstants.thumbHeight) / 2.0
        let targetFrame = CGRect(x: targetX, y: thumbY, width: SwitchConstants.thumbWidth, height: SwitchConstants.thumbHeight)

        let startFrame = self.thumbLayer.frame
        let duration = SwitchConstants.animationDuration
        let startTime = CACurrentMediaTime()

        let velocityX = (targetFrame.origin.x - startFrame.origin.x) / duration

        self.thumbPositionAnimationLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(60)) { [weak self] _ in
            guard let self else { return }

            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(elapsed / duration, 1.0)
            let easedProgress = self.easeInOut(progress)

            let currentX = startFrame.origin.x + (targetFrame.origin.x - startFrame.origin.x) * easedProgress
            let currentFrame = CGRect(x: currentX, y: thumbY, width: SwitchConstants.thumbWidth, height: SwitchConstants.thumbHeight)
            self.thumbLayer.frame = currentFrame

            self.updateLiquidGlassFrame()

            self.liquidGlassMorphAnimator?.feedVelocity(CGPoint(x: velocityX, y: 0))

            if progress >= 1.0 {
                self.thumbPositionAnimationLink?.invalidate()
                self.thumbPositionAnimationLink = nil
                completion()
            }
        }
    }

    private func easeInOut(_ t: CGFloat) -> CGFloat {
        return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !isPanning else { return }

        let newValue = !_isOn

        showLiquidGlass()

        _isOn = newValue
        visuallyOn = newValue
        updateTrackColor(animated: true)

        animateThumbToFinalPosition { [weak self] in
            guard let self else { return }
            let finalFrame = self.thumbLayer.frame
            self.hideLiquidGlass(toThumbFrame: finalFrame, animated: true)
        }

        hapticFeedback.impact(.light)
        valueChanged?(newValue)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            isPanning = true
            panStartThumbX = thumbLayer.frame.origin.x

            resetVelocityTracking(at: gesture.location(in: self))

            showLiquidGlass()

        case .changed:
            updateVelocity(at: gesture.location(in: self))

            let translation = gesture.translation(in: self)
            let newX = panStartThumbX + translation.x
            setThumbX(newX)

            updateLiquidGlassFrame()

            liquidGlassMorphAnimator?.feedVelocity(currentVelocity)

        case .ended, .cancelled:
            isPanning = false

            let currentX = thumbLayer.frame.origin.x
            let midX = (thumbMinX + thumbMaxX) / 2.0
            let newValue = currentX >= midX

            if newValue != _isOn {
                _isOn = newValue
                valueChanged?(newValue)
            }

            visuallyOn = newValue
            updateThumbPosition(animated: true)
            updateTrackColor(animated: true)

            if liquidGlassView != nil {
                let targetX = newValue ? thumbOnX : thumbOffX
                let thumbY = (bounds.height - SwitchConstants.thumbHeight) / 2.0
                let finalFrame = CGRect(x: targetX, y: thumbY, width: SwitchConstants.thumbWidth, height: SwitchConstants.thumbHeight)
                hideLiquidGlass(toThumbFrame: finalFrame, animated: true)
            }

        default:
            break
        }
    }

    deinit {
        thumbPositionAnimationLink?.invalidate()
        liquidGlassMorphAnimator?.forceStop()
    }
}

open class LiquidGlassSwitchNode: ASDisplayNode {
    public var valueUpdated: ((Bool) -> Void)?

    public var frameColor = UIColor(rgb: 0xe0e0e0) {
        didSet {
            if self.isNodeLoaded {
                if oldValue != self.frameColor {
                    if #available(iOS 26.0, *) {
                        (self.view as? UISwitch)?.tintColor = self.frameColor
                    } else {
                        (self.view as? LiquidGlassCustomSwitchView)?.offTintColor = self.frameColor
                    }
                }
            }
        }
    }

    public var handleColor = UIColor(rgb: 0xffffff) {
        didSet {
            if self.isNodeLoaded {
                if oldValue != self.handleColor {
                    if #available(iOS 26.0, *) {
                    } else {
                        (self.view as? LiquidGlassCustomSwitchView)?.thumbTintColor = self.handleColor
                    }
                }
            }
        }
    }

    public var contentColor = UIColor(rgb: 0x42d451) {
        didSet {
            if self.isNodeLoaded {
                if oldValue != self.contentColor {
                    if #available(iOS 26.0, *) {
                        (self.view as? UISwitch)?.onTintColor = self.contentColor
                    } else {
                        (self.view as? LiquidGlassCustomSwitchView)?.onTintColor = self.contentColor
                    }
                }
            }
        }
    }

    private var _isOn: Bool = false
    public var isOn: Bool {
        get {
            return self._isOn
        } set(value) {
            if (value != self._isOn) {
                self._isOn = value
                if self.isNodeLoaded {
                    if #available(iOS 26.0, *) {
                        (self.view as? UISwitch)?.setOn(value, animated: false)
                    } else {
                        (self.view as? LiquidGlassCustomSwitchView)?.isOn = value
                    }
                }
            }
        }
    }

    override public init() {
        super.init()

        self.setViewBlock({
            if #available(iOS 26.0, *) {
                return LiquidGlassSwitchNodeView()
            } else {
                return LiquidGlassCustomSwitchView()
            }
        })
    }

    override open func didLoad() {
        super.didLoad()

        self.view.isAccessibilityElement = false

        if #available(iOS 26.0, *) {
            let switchView = self.view as! UISwitch
            switchView.backgroundColor = self.backgroundColor
            switchView.tintColor = self.frameColor
            switchView.onTintColor = self.contentColor
            switchView.setOn(self._isOn, animated: false)
            switchView.addTarget(self, action: #selector(switchValueChanged(_:)), for: .valueChanged)
        } else {
            let customView = self.view as! LiquidGlassCustomSwitchView
            customView.backgroundColor = .clear
            customView.offTintColor = self.frameColor
            customView.onTintColor = self.contentColor
            customView.thumbTintColor = self.handleColor
            customView.isOn = self._isOn
            customView.valueChanged = { [weak self] value in
                self?._isOn = value
                self?.valueUpdated?(value)
            }
        }
    }

    public func setOn(_ value: Bool, animated: Bool) {
        self._isOn = value
        if self.isNodeLoaded {
            if #available(iOS 26.0, *) {
                (self.view as? UISwitch)?.setOn(value, animated: animated)
            } else {
                (self.view as? LiquidGlassCustomSwitchView)?.setOn(value, animated: animated)
            }
        }
    }

    override open func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: SwitchConstants.width, height: SwitchConstants.height)
    }

    @objc func switchValueChanged(_ view: UISwitch) {
        self._isOn = view.isOn
        self.valueUpdated?(view.isOn)
    }
}
