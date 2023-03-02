import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData

private let labelFont = Font.regular(16.0)
private let smallLabelFont = Font.regular(14.0)

private enum ToastDescription: Equatable {
    enum Key: Hashable {
        case camera
        case microphone
        case mute
        case battery
    }
    
    case camera
    case microphone
    case mute
    case battery
    
    var key: Key {
        switch self {
        case .camera:
            return .camera
        case .microphone:
            return .microphone
        case .mute:
            return .mute
        case .battery:
            return .battery
        }
    }
}

final class ContestCallControllerToastContainerNode: ASDisplayNode {
    private var toastNodes: [ToastDescription.Key: CallControllerToastItemNode] = [:]
    private var visibleToastNodes: [CallControllerToastItemNode] = []
    
    private let strings: PresentationStrings
    
    private var validLayout: (CGFloat, CGFloat)?
    
    private var content: CallControllerToastContent?
    private var appliedContent: CallControllerToastContent?
    var title: String = ""
    var light: Bool {
        didSet {
            for node in self.toastNodes.values {
                node.light = self.light
            }
        }
    }
    
    init(strings: PresentationStrings, light: Bool) {
        self.strings = strings
        self.light = light
        
        super.init()
    }
    
    private func updateToastsLayout(strings: PresentationStrings, content: CallControllerToastContent, width: CGFloat, bottomInset: CGFloat, animated: Bool) -> CGFloat {
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.3, curve: .spring)
        } else {
            transition = .immediate
        }
        
        self.appliedContent = content
        
        let spacing: CGFloat = 18.0
    
        var height: CGFloat = 0.0
        var toasts: [ToastDescription] = []
        
        if content.contains(.camera) {
            toasts.append(.camera)
        }
        if content.contains(.microphone) {
            toasts.append(.microphone)
        }
        if content.contains(.mute) {
            toasts.append(.mute)
        }
        if content.contains(.battery) {
            toasts.append(.battery)
        }
        
        var transitions: [ToastDescription.Key: (ContainedViewLayoutTransition, CGFloat, Bool)] = [:]
        var validKeys: [ToastDescription.Key] = []
        for toast in toasts {
            validKeys.append(toast.key)
            var toastTransition = transition
            var animateIn = false
            let toastNode: CallControllerToastItemNode
            if let current = self.toastNodes[toast.key] {
                toastNode = current
            } else {
                toastNode = CallControllerToastItemNode(light: self.light)
                self.toastNodes[toast.key] = toastNode
                self.addSubnode(toastNode)
                self.visibleToastNodes.append(toastNode)
                toastTransition = .immediate
                animateIn = transition.isAnimated
            }
            let toastContent: CallControllerToastItemNode.Content
            switch toast {
                case .camera:
                    toastContent = CallControllerToastItemNode.Content(
                        key: .camera,
                        image: .camera,
                        text: strings.Call_CameraOff(self.title).string
                    )
                case .microphone:
                    toastContent = CallControllerToastItemNode.Content(
                        key: .microphone,
                        image: .microphone,
                        text: strings.Call_MicrophoneOff(self.title).string
                    )
                case .mute:
                    toastContent = CallControllerToastItemNode.Content(
                        key: .mute,
                        image: .microphone,
                        text: strings.Call_YourMicrophoneOff
                    )
                case .battery:
                    toastContent = CallControllerToastItemNode.Content(
                        key: .battery,
                        image: .battery,
                        text: strings.Call_BatteryLow(self.title).string
                    )
            }
            let toastHeight = toastNode.update(width: width, content: toastContent, transition: toastTransition)
            transitions[toast.key] = (toastTransition, toastHeight, animateIn)
        }
        
        var removedKeys: [ToastDescription.Key] = []
        for (key, toastNode) in self.toastNodes {
            if !validKeys.contains(key) {
                removedKeys.append(key)
                self.visibleToastNodes.removeAll { $0 === toastNode }
                if animated {
                    toastNode.animateOut(transition: transition) { [weak toastNode] in
                        toastNode?.removeFromSupernode()
                    }
                } else {
                    toastNode.removeFromSupernode()
                }
            }
        }
        for key in removedKeys {
            self.toastNodes.removeValue(forKey: key)
        }
        
        for toastNode in self.visibleToastNodes {
            if let content = toastNode.currentContent, let (transition, toastHeight, animateIn) = transitions[content.key] {
                transition.updateFrame(node: toastNode, frame: CGRect(x: 0.0, y: height, width: width, height: toastHeight))
                height += toastHeight + spacing
                
                if animateIn {
                    toastNode.animateIn(with: 0.3)
                }
            }
        }
        if height > 0.0 {
            height -= spacing
        }
        
        return height
    }
    
    func updateLayout(strings: PresentationStrings, content: CallControllerToastContent?, constrainedWidth: CGFloat, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.validLayout = (constrainedWidth, bottomInset)
        
        self.content = content
        
        if let content = self.content {
            return self.updateToastsLayout(strings: strings, content: content, width: constrainedWidth, bottomInset: bottomInset, animated: transition.isAnimated)
        } else {
            return 0.0
        }
    }
}

private class CallControllerToastItemNode: ASDisplayNode {
    struct Content: Equatable {
        enum Image {
            case camera
            case microphone
            case battery
        }
        
        var key: ToastDescription.Key
        var image: Image
        var text: String
        
        init(key: ToastDescription.Key, image: Image, text: String) {
            self.key = key
            self.image = image
            self.text = text
        }
    }
    
    let clipNode: ASDisplayNode
    let effectView: UIVisualEffectView
    let textNode: ImmediateTextNode
    
    private(set) var currentContent: Content?
    private(set) var currentWidth: CGFloat?
    private(set) var currentHeight: CGFloat?
    var light: Bool {
        didSet {
            self.updateEffect()
        }
    }
    
    private func updateEffect() {
        if #available(iOS 13.0, *) {
            self.effectView.effect = UIBlurEffect(style: self.light ? .systemMaterialLight : .systemThinMaterialDark)
            self.effectView.alpha = self.light ? 0.3 : 0.6
        } else {
            self.effectView.effect = UIBlurEffect(style: self.light ? .light : .dark)
        }
    }
    
    init(light: Bool) {
        self.light = light
        self.clipNode = ASDisplayNode()
        self.clipNode.clipsToBounds = true
        self.clipNode.layer.cornerRadius = 14.0
        
        self.effectView = UIVisualEffectView()
        self.effectView.isUserInteractionEnabled = false
        
        self.textNode = ImmediateTextNode()
        self.textNode.maximumNumberOfLines = 2
        self.textNode.displaysAsynchronously = false
        self.textNode.isUserInteractionEnabled = false
        
        super.init()
        
        self.addSubnode(self.clipNode)
        self.clipNode.view.addSubview(self.effectView)
        self.clipNode.addSubnode(self.textNode)
    }
    
    override func didLoad() {
        super.didLoad()
        
        if #available(iOS 13.0, *) {
            self.clipNode.layer.cornerCurve = .continuous
        }
    }
    
    func update(width: CGFloat, content: Content, transition: ContainedViewLayoutTransition) -> CGFloat {
        let inset: CGFloat = 30.0
        let isNarrowScreen = width <= 320.0
        let font = isNarrowScreen ? smallLabelFont : labelFont
        let topInset: CGFloat = isNarrowScreen ? 5.0 : 4.0
                
        if self.currentContent != content || self.currentWidth != width {
            self.currentContent = content
            self.currentWidth = width
                  
            self.textNode.attributedText = NSAttributedString(string: content.text, font: font, textColor: .white)
            
            let textSize = self.textNode.updateLayout(CGSize(width: width - inset * 2.0, height: 100.0))
            
            let backgroundSize = CGSize(width: textSize.width + 12.0 * 2.0, height: max(30.0, textSize.height + 4.0 * 2.0))
            let backgroundFrame = CGRect(origin: CGPoint(x: floor((width - backgroundSize.width) / 2.0), y: 0.0), size: backgroundSize)
            
            transition.updateFrame(node: self.clipNode, frame: backgroundFrame)
            transition.updateFrame(view: self.effectView, frame: CGRect(origin: CGPoint(), size: backgroundFrame.size))

            self.textNode.frame = CGRect(origin: CGPoint(x: 12.0, y: topInset), size: textSize)
            
            self.currentHeight = backgroundSize.height
        }
        self.updateEffect()
        return self.currentHeight ?? 28.0
    }
    
    func animateIn(with delay: CGFloat) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.12)
        self.layer.animateSpring(from: 0.0 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.35, delay: delay, damping: 55.0, mass: 2.0)
    }
    
    func animateOut(transition: ContainedViewLayoutTransition, completion: @escaping () -> Void) {
        transition.updateTransformScale(node: self, scale: 0.6)
        transition.updateAlpha(node: self, alpha: 0.0, completion: { _ in
            completion()
        })
    }
}
