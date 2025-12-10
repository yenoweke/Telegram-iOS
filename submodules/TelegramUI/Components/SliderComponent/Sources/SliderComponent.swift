import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import LegacyComponents
import ComponentFlow
import LiquidGlass

public final class SliderComponent: Component {
    public final class Discrete: Equatable {
        public let valueCount: Int
        public let value: Int
        public let minValue: Int?
        public let markPositions: Bool
        public let valueUpdated: (Int) -> Void
        
        public init(valueCount: Int, value: Int, minValue: Int? = nil, markPositions: Bool, valueUpdated: @escaping (Int) -> Void) {
            self.valueCount = valueCount
            self.value = value
            self.minValue = minValue
            self.markPositions = markPositions
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Discrete, rhs: Discrete) -> Bool {
            if lhs.valueCount != rhs.valueCount {
                return false
            }
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            if lhs.markPositions != rhs.markPositions {
                return false
            }
            return true
        }
    }
    
    public final class Continuous: Equatable {
        public let value: CGFloat
        public let minValue: CGFloat?
        public let valueUpdated: (CGFloat) -> Void
        
        public init(value: CGFloat, minValue: CGFloat? = nil, valueUpdated: @escaping (CGFloat) -> Void) {
            self.value = value
            self.minValue = minValue
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Continuous, rhs: Continuous) -> Bool {
            if lhs.value != rhs.value {
                return false
            }
            if lhs.minValue != rhs.minValue {
                return false
            }
            return true
        }
    }
    
    public enum Content: Equatable {
        case discrete(Discrete)
        case continuous(Continuous)
    }
    
    public let content: Content
    public let useNative: Bool
    public let trackBackgroundColor: UIColor
    public let trackForegroundColor: UIColor
    public let minTrackForegroundColor: UIColor?
    public let knobSize: CGFloat?
    public let knobColor: UIColor?
    public let isTrackingUpdated: ((Bool) -> Void)?
    
    public init(
        content: Content,
        useNative: Bool = false,
        trackBackgroundColor: UIColor,
        trackForegroundColor: UIColor,
        minTrackForegroundColor: UIColor? = nil,
        knobSize: CGFloat? = nil,
        knobColor: UIColor? = nil,
        isTrackingUpdated: ((Bool) -> Void)? = nil
    ) {
        self.content = content
        self.useNative = useNative
        self.trackBackgroundColor = trackBackgroundColor
        self.trackForegroundColor = trackForegroundColor
        self.minTrackForegroundColor = minTrackForegroundColor
        self.knobSize = knobSize
        self.knobColor = knobColor
        self.isTrackingUpdated = isTrackingUpdated
    }
    
    public static func ==(lhs: SliderComponent, rhs: SliderComponent) -> Bool {
        if lhs.content != rhs.content {
            return false
        }
        if lhs.trackBackgroundColor != rhs.trackBackgroundColor {
            return false
        }
        if lhs.trackForegroundColor != rhs.trackForegroundColor {
            return false
        }
        if lhs.minTrackForegroundColor != rhs.minTrackForegroundColor {
            return false
        }
        if lhs.knobSize != rhs.knobSize {
            return false
        }
        if lhs.knobColor != rhs.knobColor {
            return false
        }
        return true
    }
    
    final class SliderView: UISlider {
        
    }
    
    public final class View: UIView {
        private var nativeSliderView: SliderView?
        private var liquidSliderView: LiquidSliderView?

        private var component: SliderComponent?
        private weak var state: EmptyComponentState?

        public var hitTestTarget: UIView? {
            return self.liquidSliderView
        }
        
        override public init(frame: CGRect) {
            super.init(frame: frame)
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
                
        public func cancelGestures() {
            if let liquidSliderView = self.liquidSliderView, let gestureRecognizers = liquidSliderView.gestureRecognizers {
                for gestureRecognizer in gestureRecognizers {
                    gestureRecognizer.isEnabled = false
                    gestureRecognizer.isEnabled = true
                }
            }
        }
        
        func update(component: SliderComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.state = state
            
            let size = CGSize(width: availableSize.width, height: 44.0)
            
            if #available(iOS 26.0, *), component.useNative {
                let sliderView: SliderView
                if let current = self.nativeSliderView {
                    sliderView = current
                } else {
                    sliderView = SliderView()
                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    sliderView.layer.allowsGroupOpacity = true
                    
                    self.addSubview(sliderView)
                    self.nativeSliderView = sliderView
                    
                    switch component.content {
                    case let .continuous(continuous):
                        sliderView.minimumValue = Float(continuous.minValue ?? 0.0)
                        sliderView.maximumValue = 1.0
                    case let .discrete(discrete):
                        sliderView.minimumValue = 0.0
                        sliderView.maximumValue = Float(discrete.valueCount - 1)
                        sliderView.trackConfiguration = .init(numberOfTicks: discrete.valueCount)
                    }
                }
                switch component.content {
                case let .continuous(continuous):
                    sliderView.value = Float(continuous.value)
                case let .discrete(discrete):
                    sliderView.value = Float(discrete.value)
                }
                sliderView.minimumTrackTintColor = component.trackForegroundColor
                sliderView.maximumTrackTintColor = component.trackBackgroundColor
                
                transition.setFrame(view: sliderView, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: availableSize.width, height: 44.0)))
            } else {
                let liquidSliderView: LiquidSliderView
                if let current = self.liquidSliderView {
                    liquidSliderView = current
                } else {
                    liquidSliderView = LiquidSliderView()
                    if let knobSize = component.knobSize {
                        liquidSliderView.lineSize = knobSize + 4.0
                        // Keep pill shape with proportional width
                        liquidSliderView.knobSize = CGSize(width: knobSize * (38.0 / 24.0), height: knobSize)
                    } else {
                        liquidSliderView.lineSize = 4.0
                    }
                    liquidSliderView.trackCornerRadius = liquidSliderView.lineSize * 0.5
                    liquidSliderView.dotSize = 5.0
                    liquidSliderView.minimumValue = 0.0
                    liquidSliderView.startValue = 0.0

                    switch component.content {
                    case let .discrete(discrete):
                        liquidSliderView.maximumValue = CGFloat(discrete.valueCount - 1)
                        liquidSliderView.positionsCount = discrete.valueCount
                        liquidSliderView.markPositions = discrete.markPositions
                    case .continuous:
                        liquidSliderView.maximumValue = 1.0
                    }

                    liquidSliderView.backgroundColor = nil
                    liquidSliderView.isOpaque = false
                    liquidSliderView.backColor = component.trackBackgroundColor
                    liquidSliderView.trackColor = component.trackForegroundColor
                    if let knobColor = component.knobColor {
                        liquidSliderView.knobColor = knobColor
                    }

                    liquidSliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    liquidSliderView.layer.allowsGroupOpacity = true
                    self.liquidSliderView = liquidSliderView
                    self.addSubview(liquidSliderView)
                }
                liquidSliderView.lowerBoundTrackColor = component.minTrackForegroundColor
                switch component.content {
                case let .discrete(discrete):
                    liquidSliderView.setValue(CGFloat(discrete.value))
                    if let minValue = discrete.minValue {
                        liquidSliderView.lowerBoundValue = CGFloat(minValue)
                    } else {
                        liquidSliderView.lowerBoundValue = 0.0
                    }
                case let .continuous(continuous):
                    liquidSliderView.setValue(continuous.value)
                    if let minValue = continuous.minValue {
                        liquidSliderView.lowerBoundValue = minValue
                    } else {
                        liquidSliderView.lowerBoundValue = 0.0
                    }
                }
                if let isTrackingUpdated = component.isTrackingUpdated {
                    liquidSliderView.interactionBegan = {
                        isTrackingUpdated(true)
                    }
                    liquidSliderView.interactionEnded = {
                        isTrackingUpdated(false)
                    }
                }

                transition.setFrame(view: liquidSliderView, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: availableSize.width, height: 44.0)))
            }
            
            return size
        }
        
        @objc private func sliderValueChanged() {
            guard let component = self.component else {
                return
            }
            let floatValue: CGFloat
            if let liquidSliderView = self.liquidSliderView {
                floatValue = liquidSliderView.value
            } else if let nativeSliderView = self.nativeSliderView {
                floatValue = CGFloat(nativeSliderView.value)
            } else {
                return
            }
            switch component.content {
            case let .discrete(discrete):
                discrete.valueUpdated(Int(floatValue))
            case let .continuous(continuous):
                continuous.valueUpdated(floatValue)
            }
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
