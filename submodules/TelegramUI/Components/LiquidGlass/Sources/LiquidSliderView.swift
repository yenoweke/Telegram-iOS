import Foundation
import UIKit
import Display

private enum SliderConstants {
    static let lineSize: CGFloat = 6.0
    static let margin: CGFloat = 15.0
    static let internalMargin: CGFloat = 7.0
    static let dotSize: CGFloat = 3.0
    static let defaultKnobSize: CGSize = CGSize(width: 38.0, height: 24.0)
    static let edgeFactor: CGFloat = defaultKnobSize.width * 0.25

    static let liquidGlassExpandScale: CGFloat = 1.5
    static let liquidGlassAnimationDuration: TimeInterval = 0.2
    static let liquidGlassCapturePadding: CGPoint = CGPoint(x: 0.0, y: 0.0)

    static let viscosityTransitionForward: CGFloat = 0.65
    static let viscosityTransitionBackward: CGFloat = 1.0 - viscosityTransitionForward
    static let knobSnapThreshold: CGFloat = 0.65
}

public final class LiquidSliderView: UIControl {

    public var minimumValue: CGFloat = 0.0 {
        didSet {
            if minimumValue != oldValue {
                setNeedsLayout()
            }
        }
    }

    public var maximumValue: CGFloat = 1.0 {
        didSet {
            if maximumValue != oldValue {
                setNeedsLayout()
            }
        }
    }

    public var startValue: CGFloat = 0.0 {
        didSet {
            if startValue != oldValue {
                setNeedsLayout()
            }
        }
    }

    public var lowerBoundValue: CGFloat = 0.0 {
        didSet {
            if lowerBoundValue != oldValue {
                setNeedsLayout()
            }
        }
    }

    public private(set) var value: CGFloat = 0.0

    public var positionsCount: Int = 0 {
        didSet {
            if positionsCount != oldValue {
                updatePositionDots()
                setNeedsLayout()
            }
        }
    }

    public var disableSnapToPositions: Bool = false

    public var markPositions: Bool = true {
        didSet {
            if markPositions != oldValue {
                updatePositionDots()
                setNeedsLayout()
            }
        }
    }

    public var dotSize: CGFloat = SliderConstants.dotSize {
        didSet {
            if dotSize != oldValue {
                updatePositionDots()
                setNeedsLayout()
            }
        }
    }

    public var backColor: UIColor = UIColor(white: 0.8, alpha: 1.0) {
        didSet {
            updateColors()
        }
    }

    public var trackColor: UIColor = UIColor(white: 0.4, alpha: 1.0) {
        didSet {
            updateColors()
        }
    }

    public var lowerBoundTrackColor: UIColor? {
        didSet {
            updateColors()
        }
    }

    public var lineSize: CGFloat = SliderConstants.lineSize {
        didSet {
            if lineSize != oldValue {
                setNeedsLayout()
            }
        }
    }

    public var trackCornerRadius: CGFloat = SliderConstants.lineSize / 2.0 {
        didSet {
            if trackCornerRadius != oldValue {
                setNeedsLayout()
            }
        }
    }

    private var _knobSize: CGSize = SliderConstants.defaultKnobSize
    public var knobSize: CGSize {
        get { _knobSize }
        set {
            if _knobSize != newValue {
                _knobSize = newValue
                updateKnobImage()
                cachedMetrics = nil
                setNeedsLayout()
            }
        }
    }

    public var knobColor: UIColor = .white {
        didSet {
            if knobColor != oldValue {
                updateKnobImage()
            }
        }
    }

    public var limitValueChangedToLatestState: Bool = false

    public private(set) var knobStartedDragging: Bool = false

    public var interactionBegan: (() -> Void)?
    public var interactionEnded: (() -> Void)?

    private let trackBackgroundLayer = SimpleLayer()
    private let trackForegroundLayer = SimpleLayer()
    private let knobContainerView = UIView()
    private let knobImageView = UIImageView()
    private var positionDotLayers: [SimpleLayer] = []

    private var knobTouchStart: CGFloat = 0
    private var knobTouchCenterStart: CGFloat = 0
    private var _isTracking: Bool = false

    private var discreteCurrentPosition: Int = 0

    private enum AnimationState {
        case idle
        case tracking
        case animatingShow
        case animatingHide
    }

    private var animationState: AnimationState = .idle

    private var liquidGlassCenterX: CGFloat = 0

    private var springVelocity: CGFloat = 0
    private var springScaleCurrent: CGFloat = 1.0
    private var springScaleTarget: CGFloat = 1.0

    private let showSpringStiffness: CGFloat = 0.58
    private let showSpringDamping: CGFloat = 0.62

    private var hideAnimationStartTime: CFTimeInterval = 0
    private var hideAnimationStartPosition: CGFloat = 0
    private var hideAnimationTargetPosition: CGFloat = 0
    private let hideAnimationDuration: CFTimeInterval = 0.25

    private var showAnimationStartTime: CFTimeInterval = 0
    private let showAnimationDuration: CFTimeInterval = 0.25

    private var displayLink: SharedDisplayLinkDriver.Link?

    private var needsFrameUpdate: Bool = false

    private struct LayoutMetrics {
        let edgeMargin: CGFloat
        let totalLength: CGFloat
        let trackPadding: CGFloat
        let sideLength: CGFloat
        let knobImageSize: CGSize

        var isValid: Bool { totalLength > 0 && knobImageSize.width > 0 }
    }
    private var cachedMetrics: LayoutMetrics?


    private let hapticFeedback = HapticFeedback()

    private lazy var panGestureRecognizer: UIPanGestureRecognizer = {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = self
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = false
        return recognizer
    }()

    private var liquidGlassView: LiquidGlassView?
    private var liquidGlassMorphAnimator: LiquidGlassMorphAnimator?

    private var lastPanPosition: CGPoint = .zero
    private var lastPanTime: CFTimeInterval = 0
    private var currentVelocity: CGPoint = .zero


    public override var isTracking: Bool {
        _isTracking
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false

        setupLayers()
        setupHaptics()
        setupGestureRecognizers()
        updateKnobImage()

        self.interactiveTransitionGestureRecognizerTest = { [weak self] point in
            guard let self = self else { return false }
            let knobHitArea = self.knobContainerView.frame.insetBy(dx: -10, dy: -10)
            return knobHitArea.contains(point)
        }
    }

    private func setupLayers() {
        layer.addSublayer(trackBackgroundLayer)
        layer.addSublayer(trackForegroundLayer)

        knobContainerView.isUserInteractionEnabled = false
        knobContainerView.addSubview(knobImageView)
        addSubview(knobContainerView)

        updateColors()
    }

    private func setupHaptics() {
        hapticFeedback.prepareTap()
    }

    private func setupGestureRecognizers() {
        addGestureRecognizer(panGestureRecognizer)
    }

    private func updateKnobImage() {
        let image = generateDefaultKnobImage(size: knobSize, color: knobColor)
        knobImageView.image = image
        knobImageView.frame = CGRect(origin: .zero, size: image.size)
        cachedMetrics = nil
    }

    private func generateDefaultKnobImage(size: CGSize, color: UIColor) -> UIImage {
        let shadowPadding: CGFloat = 2.0
        let imageSize = CGSize(
            width: size.width + shadowPadding * 2,
            height: size.height + shadowPadding * 2
        )
        let cornerRadius = size.height / 2.0

        return UIGraphicsImageRenderer(size: imageSize).image { ctx in
            let context = ctx.cgContext

            context.setShadow(
                offset: .zero,
                blur: 2.0,
                color: UIColor(white: 0, alpha: 0.15).cgColor
            )
            context.setFillColor(color.cgColor)

            let knobRect = CGRect(
                x: shadowPadding,
                y: shadowPadding,
                width: size.width,
                height: size.height
            )
            let path = UIBezierPath(roundedRect: knobRect, cornerRadius: cornerRadius)
            context.addPath(path.cgPath)
            context.fillPath()
        }
    }

    private func updateColors() {
        trackBackgroundLayer.backgroundColor = backColor.cgColor
        trackForegroundLayer.backgroundColor = trackColor.cgColor
    }

    private func updatePositionDots() {
        for dotLayer in positionDotLayers {
            dotLayer.removeFromSuperlayer()
        }
        positionDotLayers.removeAll()

        guard positionsCount > 1 else { return }

        for i in 0..<positionsCount {
            if !markPositions && i != 0 && i != positionsCount - 1 {
                continue
            }

            let outerDot = SimpleLayer()
            let innerDot = SimpleLayer()
            outerDot.addSublayer(innerDot)

            layer.insertSublayer(outerDot, below: knobContainerView.layer)
            positionDotLayers.append(outerDot)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard !bounds.isEmpty else { return }

        if cachedMetrics == nil || cachedMetrics!.sideLength != bounds.height {
            updateLayoutMetrics()
        }

        guard animationState == .idle else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        layoutTrack()
        layoutKnob()
        layoutPositionDots()

        CATransaction.commit()
    }

    private func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = max(0, min(1, x))
        return t * t * (3 - 2 * t)
    }

    /// Asymmetric easeInOutQuint with adjustable transition point yenoweke
    /// - Parameters:
    ///   - x: Input value 0...1
    ///   - transitionX: Where the curve transitions from ease-in to ease-out (0.5 = symmetric)
    /// - Returns: Eased value 0...1
    private func asymmetricEaseInOutQuint(_ x: CGFloat, transitionX: CGFloat) -> CGFloat {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }

        if x < transitionX {
            let t = x / transitionX
            return pow(t, 5) * 0.5
        } else {
            let t = (x - transitionX) / (1.0 - transitionX)
            return 0.5 + (1.0 - pow(1.0 - t, 5)) * 0.5
        }
    }

    private func easeInOutQuad(_ t: CGFloat) -> CGFloat {
        return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    private func calculateFillWidth(
        knobPosition: CGFloat,
        boundsWidth: CGFloat,
        edgeMargin: CGFloat,
        trackPadding: CGFloat
    ) -> CGFloat {
        let edgeFactor = SliderConstants.edgeFactor

        let leftEdgeEnd = edgeMargin + edgeFactor
        let rightEdgeStart = boundsWidth - edgeMargin - edgeFactor

        var fillEndPosition: CGFloat

        if knobPosition <= edgeMargin {
            fillEndPosition = trackPadding
        } else if knobPosition >= boundsWidth - edgeMargin {
            fillEndPosition = boundsWidth - trackPadding
        } else if knobPosition < leftEdgeEnd {
            let t = (knobPosition - edgeMargin) / edgeFactor
            fillEndPosition = trackPadding + smoothstep(t) * (leftEdgeEnd - trackPadding)
        } else if knobPosition > rightEdgeStart {
            let t = (knobPosition - rightEdgeStart) / edgeFactor
            fillEndPosition = rightEdgeStart + smoothstep(t) * (boundsWidth - trackPadding - rightEdgeStart)
        } else {
            fillEndPosition = knobPosition
        }

        return max(0, fillEndPosition - trackPadding)
    }

    private func layoutTrack() {
        if cachedMetrics == nil || !(cachedMetrics?.isValid ?? false) {
            updateLayoutMetrics()
        }

        guard let metrics = cachedMetrics, metrics.isValid else { return }

        let edgeMargin = metrics.edgeMargin
        let totalLength = metrics.totalLength
        let trackPadding = metrics.trackPadding
        let sideLength = metrics.sideLength
        let knobImageSize = metrics.knobImageSize

        let backFrame = CGRect(
            x: trackPadding,
            y: (sideLength - lineSize) / 2,
            width: bounds.width - trackPadding * 2,
            height: lineSize
        )

        trackBackgroundLayer.frame = backFrame
        trackBackgroundLayer.cornerRadius = trackCornerRadius

        let knobCenterPosition = edgeMargin + centerPositionForValue(value, totalLength: totalLength, knobSize: knobImageSize.width)

        let track = calculateFillWidth(
            knobPosition: knobCenterPosition,
            boundsWidth: bounds.width,
            edgeMargin: edgeMargin,
            trackPadding: trackPadding
        )

        let trackFrame = CGRect(
            x: trackPadding,
            y: (sideLength - lineSize) / 2,
            width: track,
            height: lineSize
        )

        trackForegroundLayer.frame = trackFrame
        trackForegroundLayer.cornerRadius = trackCornerRadius
    }

    private func layoutKnob() {
        if cachedMetrics == nil || !(cachedMetrics?.isValid ?? false) {
            updateLayoutMetrics()
        }

        guard let metrics = cachedMetrics, metrics.isValid else { return }

        let edgeMargin = metrics.edgeMargin
        let totalLength = metrics.totalLength
        let sideLength = metrics.sideLength
        let knobImageSize = metrics.knobImageSize

        let knobCenterPosition = edgeMargin + centerPositionForValue(value, totalLength: totalLength, knobSize: knobImageSize.width)

        let knobFrame = CGRect(
            x: knobCenterPosition - knobImageSize.width / 2,
            y: (sideLength - knobImageSize.height) / 2,
            width: knobImageSize.width,
            height: knobImageSize.height
        )

        knobContainerView.frame = knobFrame
        knobImageView.center = CGPoint(x: knobFrame.width / 2, y: knobFrame.height / 2)
    }

    private func layoutPositionDots() {
        guard positionsCount > 1 else { return }

        if cachedMetrics == nil || !(cachedMetrics?.isValid ?? false) {
            updateLayoutMetrics()
        }

        guard let metrics = cachedMetrics, metrics.isValid else { return }

        let edgeMargin = metrics.edgeMargin
        let totalLength = metrics.totalLength
        let sideLength = metrics.sideLength

        let dotOffset: CGFloat = 4.0
        let trackCenterY = sideLength / 2
        let trackBottom = trackCenterY + lineSize / 2

        var dotIndex = 0
        for i in 0..<positionsCount {
            if !markPositions && i != 0 && i != positionsCount - 1 {
                continue
            }

            guard dotIndex < positionDotLayers.count else { break }
            let outerDot = positionDotLayers[dotIndex]
            dotIndex += 1

            let inset: CGFloat = 1.5
            let outerSize = dotSize + inset * 2

            let dotCenterPosition = edgeMargin + totalLength / CGFloat(positionsCount - 1) * CGFloat(i)

            let dotY = trackBottom + dotOffset

            let dotRect = CGRect(
                x: dotCenterPosition - outerSize / 2,
                y: dotY,
                width: outerSize,
                height: outerSize
            )

            outerDot.frame = dotRect
            outerDot.cornerRadius = outerSize / 2
            outerDot.backgroundColor = UIColor.clear.cgColor

            if let innerDot = outerDot.sublayers?.first as? SimpleLayer {
                let innerRect = CGRect(x: inset, y: inset, width: dotSize, height: dotSize)
                innerDot.frame = innerRect
                innerDot.cornerRadius = dotSize / 2

                innerDot.backgroundColor = backColor.cgColor
            }
        }
    }

    private func updateLayoutMetrics() {
        let knobImageSize = knobImageView.image?.size ?? knobSize
        let edgeMargin = knobImageSize.width / 2.0
        let totalLength = bounds.width - edgeMargin * 2

        cachedMetrics = LayoutMetrics(
            edgeMargin: edgeMargin,
            totalLength: totalLength,
            trackPadding: 2.0,
            sideLength: bounds.height,
            knobImageSize: knobImageSize
        )
    }

    private func updateKnobFrameDirect(knobCenterX: CGFloat, metrics: LayoutMetrics) {
        let sideLength = metrics.sideLength
        let knobImageSize = metrics.knobImageSize

        let knobFrame = CGRect(
            x: knobCenterX - knobImageSize.width / 2,
            y: (sideLength - knobImageSize.height) / 2,
            width: knobImageSize.width,
            height: knobImageSize.height
        )

        knobContainerView.frame = knobFrame
        knobImageView.center = CGPoint(x: knobFrame.width / 2, y: knobFrame.height / 2)
    }

    private func updateTrackFramesDirect(knobCenterX: CGFloat, metrics: LayoutMetrics) {
        let edgeMargin = metrics.edgeMargin
        let trackPadding = metrics.trackPadding
        let sideLength = metrics.sideLength

        let track = calculateFillWidth(
            knobPosition: knobCenterX,
            boundsWidth: bounds.width,
            edgeMargin: edgeMargin,
            trackPadding: trackPadding
        )

        let trackFrame = CGRect(
            x: trackPadding,
            y: (sideLength - lineSize) / 2,
            width: track,
            height: lineSize
        )

        trackForegroundLayer.frame = trackFrame
    }

    private func updateLiquidGlassFrameDirect(knobCenterX: CGFloat, metrics: LayoutMetrics) {
        guard let glass = liquidGlassView,
              let container = liquidGlassContainer else { return }

        let sideLength = metrics.sideLength
        let knobImageSize = metrics.knobImageSize

        let knobFrame = CGRect(
            x: knobCenterX - knobImageSize.width / 2,
            y: (sideLength - knobImageSize.height) / 2,
            width: knobImageSize.width,
            height: knobImageSize.height
        )

        let targetFrame = liquidGlassFrame(for: knobFrame)
        let targetFrameInContainer = convert(targetFrame, to: container)

        glass.frame = targetFrameInContainer
    }

    private func updateAllFramesFromLiquidGlass(metrics: LayoutMetrics) {
        let clampedCenterX = max(metrics.edgeMargin, min(liquidGlassCenterX, metrics.edgeMargin + metrics.totalLength))

        let knobCenterX = knobCenterFromLiquidGlass(clampedCenterX)

        updateKnobFrameDirect(knobCenterX: knobCenterX, metrics: metrics)
        updateTrackFramesDirect(knobCenterX: knobCenterX, metrics: metrics)
        updateLiquidGlassFrameDirect(knobCenterX: knobCenterX, metrics: metrics)
    }

    private func centerPositionForValue(_ value: CGFloat, totalLength: CGFloat, knobSize: CGFloat) -> CGFloat {
        if minimumValue < 0 {
            let knob = knobSize

            if abs(minimumValue) > 1.0 && Int(value) == 0 {
                return totalLength / 2
            } else if abs(value) < 0.01 {
                return totalLength / 2
            } else {
                let edgeValue = value > 0 ? maximumValue : minimumValue
                if value > 0 {
                    return ((totalLength + knob) / 2) + ((totalLength - knob) / 2) * abs(value / edgeValue)
                } else {
                    return ((totalLength - knob) / 2) * abs((edgeValue - self.value) / edgeValue)
                }
            }
        }

        let position = totalLength / (maximumValue - minimumValue) * (abs(minimumValue) + value)
        return position
    }

    private func valueForCenterPosition(_ position: CGFloat, totalLength: CGFloat, knobSize: CGFloat) -> CGFloat {
        var value: CGFloat = 0

        if minimumValue < 0 {
            let knob = knobSize

            if position < (totalLength - knob) / 2 {
                let edgeValue = minimumValue
                value = edgeValue + position / ((totalLength - knob) / 2) * abs(edgeValue)
            } else if position >= (totalLength - knob) / 2 && position <= (totalLength + knob) / 2 {
                value = 0
            } else if position > (totalLength + knob) / 2 {
                value = (position - ((totalLength + knob) / 2)) / ((totalLength - knob) / 2) * maximumValue
            }
        } else {
            value = minimumValue + position / totalLength * (maximumValue - minimumValue)
        }

        return min(max(value, minimumValue), maximumValue)
    }

    private func knobCenterFromLiquidGlass(_ liquidGlassCenterX: CGFloat) -> CGFloat {
        return liquidGlassCenterX
    }

    private func valueFromKnobCenter(_ knobCenterX: CGFloat, metrics: LayoutMetrics) -> CGFloat {
        let normalizedPos = knobCenterX - metrics.edgeMargin
        return valueForCenterPosition(normalizedPos, totalLength: metrics.totalLength, knobSize: metrics.knobImageSize.width)
    }

    private func knobCenterFromValue(_ value: CGFloat, metrics: LayoutMetrics) -> CGFloat {
        let normalizedPos = centerPositionForValue(value, totalLength: metrics.totalLength, knobSize: metrics.knobImageSize.width)
        return metrics.edgeMargin + normalizedPos
    }

    public func setValue(_ newValue: CGFloat, animated: Bool = false) {
        var clampedValue = max(minimumValue, min(maximumValue, newValue))
        if lowerBoundValue > .ulpOfOne {
            clampedValue = max(lowerBoundValue, clampedValue)
        }

        value = clampedValue
        if _isTracking == false {
            setNeedsLayout()
        }
    }

    public func increase() {
        setValue(min(maximumValue, value + 1))
        sendActions(for: .valueChanged)
    }

    public func increaseBy(_ delta: CGFloat) {
        setValue(min(maximumValue, value + delta))
        sendActions(for: .valueChanged)
    }

    public func decrease() {
        setValue(max(minimumValue, value - 1))
        sendActions(for: .valueChanged)
    }

    public func decreaseBy(_ delta: CGFloat) {
        setValue(max(minimumValue, value - delta))
        sendActions(for: .valueChanged)
    }

    public override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)
        let knobHitArea = knobContainerView.frame.insetBy(dx: -10, dy: -10)
        guard knobHitArea.contains(location) else {
            return false
        }

        handleBeginTracking(location)
        return true
    }

    public override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let location = touch.location(in: self)
        return handleContinueTracking(location)
    }

    public override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        handleEndTracking()
    }

    public override func cancelTracking(with event: UIEvent?) {
        handleCancelTracking()
    }

    private func handleBeginTracking(_ location: CGPoint) {
        _isTracking = true
        knobStartedDragging = false

        knobTouchCenterStart = knobContainerView.center.x
        knobTouchStart = location.x

        if positionsCount > 1 {
            let normalizedValue = (value - minimumValue) / (maximumValue - minimumValue)
            discreteCurrentPosition = Int(round(normalizedValue * CGFloat(positionsCount - 1)))
        }

        resetVelocityTracking(at: location)

        hapticFeedback.prepareTap()

        maybeCancelParentScrollView(superview, depth: 0)

        showLiquidGlass()
    }

    private func handleContinueTracking(_ location: CGPoint) -> Bool {
        let delta = abs(location.x - knobTouchStart)
        if delta > 1.0 && !knobStartedDragging {
            knobStartedDragging = true
            interactionBegan?()

            if animationState == .animatingShow {
                finalizeShowAnimation()
            }
        }

        updateVelocity(at: location)

        guard let metrics = cachedMetrics, metrics.isValid else { return true }

        let edgeMargin = metrics.edgeMargin
        let totalLength = metrics.totalLength
        let knobImageSize = metrics.knobImageSize

        var newCenterX = knobTouchCenterStart - knobTouchStart + location.x

        newCenterX = max(edgeMargin, min(newCenterX, edgeMargin + totalLength))

        let normalizedPosition = newCenterX - edgeMargin

        let previousValue = value

        if positionsCount > 1 && !disableSnapToPositions {
            let stepSize = totalLength / CGFloat(positionsCount - 1)
            let anchorX = CGFloat(discreteCurrentPosition) * stepSize

            let fingerDelta = normalizedPosition - anchorX
            let direction: CGFloat = fingerDelta >= 0 ? 1.0 : -1.0
            let fingerProgress = min(abs(fingerDelta) / stepSize, 1.0)

            let transitionX = direction > 0
                ? SliderConstants.viscosityTransitionForward
                : SliderConstants.viscosityTransitionBackward
            let knobProgress = asymmetricEaseInOutQuint(fingerProgress, transitionX: transitionX)

            let viscousNormalizedPosition = anchorX + direction * knobProgress * stepSize
            liquidGlassCenterX = edgeMargin + viscousNormalizedPosition

            if knobProgress >= SliderConstants.knobSnapThreshold {
                let targetPosition = discreteCurrentPosition + Int(direction)
                let lowerBoundPosition = lowerBoundValue > 0 ? Int(lowerBoundValue) : 0
                let newPosition = max(lowerBoundPosition, min(positionsCount - 1, targetPosition))

                if newPosition != discreteCurrentPosition {
                    discreteCurrentPosition = newPosition
                    let newValue = minimumValue + (maximumValue - minimumValue) * CGFloat(newPosition) / CGFloat(positionsCount - 1)
                    setValue(newValue)
                    triggerHapticFeedback()
                }
            }
        } else {
            if lowerBoundValue > 0 {
                let lowerBoundNormalized = lowerBoundValue * totalLength
                let clampedNormalized = max(normalizedPosition, lowerBoundNormalized)
                liquidGlassCenterX = edgeMargin + clampedNormalized
            } else {
                liquidGlassCenterX = newCenterX
            }

            let normalizedPos = liquidGlassCenterX - edgeMargin
            setValue(valueForCenterPosition(normalizedPos, totalLength: totalLength, knobSize: knobImageSize.width))

            if previousValue != value && !disableSnapToPositions {
                let shouldTriggerHaptic = value == minimumValue ||
                    value == maximumValue ||
                    (minimumValue != startValue && value == startValue)

                if shouldTriggerHaptic {
                    triggerHapticFeedback()
                }
            }
        }

        liquidGlassMorphAnimator?.feedVelocity(currentVelocity)

        needsFrameUpdate = true

        if !limitValueChangedToLatestState {
            sendActions(for: .valueChanged)
        }

        return true
    }

    private func handleEndTracking() {
        var finalKnobFrame = knobContainerView.frame

        if positionsCount > 1 && !disableSnapToPositions {
            guard let metrics = cachedMetrics, metrics.isValid else { return }
            let finalKnobCenterX = metrics.edgeMargin + CGFloat(discreteCurrentPosition) * metrics.totalLength / CGFloat(positionsCount - 1)
            finalKnobFrame = CGRect(
                x: finalKnobCenterX - metrics.knobImageSize.width / 2,
                y: (bounds.height - metrics.knobImageSize.height) / 2,
                width: metrics.knobImageSize.width,
                height: metrics.knobImageSize.height
            )
        }

        _isTracking = false

        sendActions(for: .valueChanged)
        setNeedsLayout()

        interactionEnded?()

        hideLiquidGlass(animated: true, targetKnobFrame: finalKnobFrame)
    }

    private func handleCancelTracking() {
        _isTracking = false
        setNeedsLayout()
        interactionEnded?()

        hideLiquidGlass(animated: true)
    }

    private func resetVelocityTracking(at point: CGPoint) {
        lastPanPosition = point
        lastPanTime = CACurrentMediaTime()
        currentVelocity = .zero
    }

    private func updateVelocity(at point: CGPoint) {
        let currentTime = CACurrentMediaTime()
        let dt = currentTime - lastPanTime

        if dt > 0.001 {
            currentVelocity = CGPoint(
                x: (point.x - lastPanPosition.x) / dt,
                y: (point.y - lastPanPosition.y) / dt
            )
        }

        lastPanPosition = point
        lastPanTime = currentTime
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(60)) { [weak self] _ in
            self?.displayLinkTick()
        }
        displayLink?.isPaused = false
    }

    private func stopDisplayLink() {
        displayLink?.isPaused = true
        displayLink?.invalidate()
        displayLink = nil
    }

    private func displayLinkTick() {
        guard let metrics = cachedMetrics, metrics.isValid else { return }

        switch animationState {
        case .idle:
            stopDisplayLink()

        case .tracking:
            guard needsFrameUpdate else { return }
            updateAllFramesFromLiquidGlass(metrics: metrics)
            needsFrameUpdate = false

        case .animatingShow:
            updateShowAnimation()
            updateAllFramesFromLiquidGlass(metrics: metrics)

        case .animatingHide:
            updateHideAnimation()
            updateAllFramesFromLiquidGlass(metrics: metrics)
        }
    }

    private func updateShowAnimation() {
        let elapsed = CACurrentMediaTime() - showAnimationStartTime
        let progress = min(1.0, CGFloat(elapsed / showAnimationDuration))
        let easedProgress = easeInOutQuad(progress)

        let currentAlpha = easedProgress

        let scaleForce = (springScaleTarget - springScaleCurrent) * showSpringStiffness
        springVelocity += scaleForce
        springVelocity *= showSpringDamping
        springScaleCurrent += springVelocity

        if let glass = liquidGlassView {
            glass.layer.transform = CATransform3DMakeScale(springScaleCurrent, springScaleCurrent, 1.0)
            glass.alpha = currentAlpha
        }

        let timeDone = progress >= 1.0
        let scaleSettled = abs(springScaleCurrent - springScaleTarget) < 0.001 && abs(springVelocity) < 0.001

        if timeDone && scaleSettled {
            finalizeShowAnimation()
        }
    }

    private func finalizeShowAnimation() {
        if let glass = liquidGlassView {
            glass.layer.transform = CATransform3DIdentity
            glass.alpha = 1.0
        }

        springScaleCurrent = 1.0
        springVelocity = 0

        animationState = .tracking
    }

    private func updateHideAnimation() {
        guard liquidGlassView != nil else {
            finalizeHideAnimation()
            return
        }

        let elapsed = CACurrentMediaTime() - hideAnimationStartTime
        let progress = min(1.0, CGFloat(elapsed / hideAnimationDuration))
        let easedProgress = easeInOutQuad(progress)

        liquidGlassCenterX = hideAnimationStartPosition + (hideAnimationTargetPosition - hideAnimationStartPosition) * easedProgress

        let currentAlpha = 1.0 - easedProgress

        let currentScale = 1.0 + (springScaleTarget - 1.0) * easedProgress

        if let glass = liquidGlassView {
            glass.layer.transform = CATransform3DMakeScale(currentScale, currentScale, 1.0)
            glass.alpha = currentAlpha
        }

        knobImageView.alpha = 1.0 - currentAlpha

        if progress >= 1.0 {
            finalizeHideAnimation()
        }
    }

    private func finalizeHideAnimation() {
        if let glass = liquidGlassView {
            glass.pauseRendering()
            glass.removeFromSuperview()
        }
        liquidGlassView = nil
        liquidGlassMorphAnimator = nil

        knobImageView.alpha = 1.0

        springVelocity = 0
        springScaleCurrent = 1.0

        animationState = .idle
        stopDisplayLink()
    }

    private func triggerHapticFeedback() {
        hapticFeedback.tap()
    }

    private func maybeCancelParentScrollView(_ view: UIView?, depth: Int) {
        guard depth <= 5, let view = view else { return }

        if let scrollView = view as? UIScrollView {
            scrollView.isScrollEnabled = false
            scrollView.isScrollEnabled = true
        } else {
            maybeCancelParentScrollView(view.superview, depth: depth + 1)
        }
    }

    private var liquidGlassContainer: UIView? {
        liquidGlassSourceView?.superview
    }

    private var liquidGlassSourceView: UIView? {
        let currentSize = frame.size
        var current = superview
        var depth = 0
        let maxDepth = 5
        while let view = current, depth < maxDepth {
            let viewSize = view.frame.size
            if viewSize.width > currentSize.width && viewSize.height > currentSize.height {
                return view
            }
            current = view.superview
            depth += 1
        }
        return superview
    }

    private func setupLiquidGlassIfNeeded() {
        guard liquidGlassView == nil else { return }
        guard let container = liquidGlassContainer,
              let sourceView = liquidGlassSourceView else { return }

        var config = LiquidGlassConfiguration()
        config.refThickness = 8
        config.shapePadding = CGPoint(x: 10, y: 10)
        config.capturePadding = SliderConstants.liquidGlassCapturePadding
        config.cornerRadius = knobSize.height * SliderConstants.liquidGlassExpandScale / 2.0
        config.blurRadius = 2.0

        let glass = LiquidGlassView(configuration: config)
        glass.sourceView = sourceView
        glass.isHidden = true
        container.addSubview(glass)
        liquidGlassView = glass

        var morphConfig = LiquidGlassMorphAnimatorConfiguration()
        morphConfig.springStiffness = 0.06
        morphConfig.springDamping = 0.85
        morphConfig.sizeFactor = 0.5
        morphConfig.squishFactor = 0.7
        morphConfig.morphRange = 0.15

        let morphAnimator = LiquidGlassMorphAnimator(configuration: morphConfig)
        morphAnimator.onMorphScaleChanged = { [weak glass] scale in
            glass?.setMorphScale(scale)
        }
        liquidGlassMorphAnimator = morphAnimator
    }

    private func liquidGlassFrame(for knobFrame: CGRect) -> CGRect {
        let expandedSize = CGSize(
            width: knobSize.width * SliderConstants.liquidGlassExpandScale,
            height: knobSize.height * SliderConstants.liquidGlassExpandScale
        )
        return CGRect(
            x: knobFrame.midX - expandedSize.width / 2,
            y: knobFrame.midY - expandedSize.height / 2,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }

    private func showLiquidGlass() {
        if animationState == .animatingHide {
            finalizeHideAnimation()
        }

        knobImageView.layer.removeAllAnimations()

        setupLiquidGlassIfNeeded()
        guard let glass = liquidGlassView,
              let container = liquidGlassContainer else { return }

        liquidGlassCenterX = knobContainerView.center.x

        let knobFrame = knobContainerView.frame
        let targetFrame = liquidGlassFrame(for: knobFrame)
        let targetFrameInContainer = convert(targetFrame, to: container)

        glass.frame = targetFrameInContainer
        glass.configuration.cornerRadius = targetFrame.height / 2.0

        let scaleX = knobFrame.width / targetFrame.width
        springScaleCurrent = scaleX
        springScaleTarget = 1.0
        springVelocity = 0

        showAnimationStartTime = CACurrentMediaTime()

        glass.layer.transform = CATransform3DMakeScale(scaleX, scaleX, 1.0)
        glass.alpha = 0
        glass.isHidden = false

        knobImageView.alpha = 0

        animationState = .animatingShow
        startDisplayLink()

        liquidGlassMorphAnimator?.start()
    }

    private func hideLiquidGlass(animated: Bool, targetKnobFrame: CGRect? = nil) {
        if animationState == .animatingShow {
            finalizeShowAnimation()
        }

        guard liquidGlassView != nil else {
            knobImageView.alpha = 1.0
            animationState = .idle
            return
        }

        liquidGlassMorphAnimator?.stop()

        let knobFrame = targetKnobFrame ?? knobContainerView.frame
        let targetFrame = liquidGlassFrame(for: knobFrame)

        if !animated {
            finalizeHideAnimation()
            return
        }

        hideAnimationStartTime = CACurrentMediaTime()
        hideAnimationStartPosition = liquidGlassCenterX
        hideAnimationTargetPosition = knobFrame.midX
        springScaleTarget = knobFrame.width / targetFrame.width

        animationState = .animatingHide
        if displayLink == nil {
            startDisplayLink()
        }
    }

    public override func willMove(toSuperview newSuperview: UIView?) {
        super.willMove(toSuperview: newSuperview)

        if newSuperview == nil && animationState != .idle {
            finalizeHideAnimation()
        }
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44.0)
    }

    deinit {
        liquidGlassMorphAnimator?.forceStop()
        stopDisplayLink()
    }
}

extension LiquidSliderView: UIGestureRecognizerDelegate {
    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return true
        }

        let location = gestureRecognizer.location(in: self)
        let knobHitArea = knobContainerView.frame.insetBy(dx: -10, dy: -10)
        guard knobHitArea.contains(location) else {
            return false
        }
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = panGesture.velocity(in: self)

            if abs(velocity.x) > abs(velocity.y) {
                return true
            } else {
                return false
            }
        }

        return true
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        guard gestureRecognizer === panGestureRecognizer else {
            return false
        }
        return true
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return false
    }
}
