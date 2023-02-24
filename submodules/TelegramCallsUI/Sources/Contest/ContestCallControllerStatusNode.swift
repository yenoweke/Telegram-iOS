import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit

private let regularNameFont = Font.regular(28.0)
private let regularStatusFont = Font.regular(16.0)
private let regularReceptionFont = Font.regular(16.0)
private let minDotSize: CGFloat = 2.0
private let indicatorAnimationDuration: TimeInterval = 0.45

private final class ContestCallProgressIndicator: ASDisplayNode {
    private let nodes: [ASDisplayNode] = [
        ASDisplayNode(),
        ASDisplayNode(),
        ASDisplayNode()
    ]
    
    var size: CGSize {
        CGSize(width: 15.0, height: 4.0)
    }
    
    override init() {
        super.init()
        nodes.forEach { node in
            node.backgroundColor = .white
            node.cornerRadius = minDotSize / 2
            node.clipsToBounds = true
            self.addSubnode(node)
        }
    }
    
    func startAnimating() {
        var frame = CGRect(x: 0, y: 0, width: minDotSize, height: minDotSize)
        var delay: TimeInterval = 0
        for node in nodes {
            node.frame = frame
            frame.origin.x += 5
            
            if delay == 0 {
                node.layer.add(self.makeAnimation(), forKey: "scaleAnimation")
            } else {
                Queue.mainQueue().after(delay) { [weak self, weak node] in
                    guard let strongSelf = self else {
                        return
                    }
                    node?.layer.add(strongSelf.makeAnimation(), forKey: "scaleAnimation")
                }
            }
            delay += indicatorAnimationDuration / Double(nodes.count)
        }
    }
    
    func stopAnimating() {
        for node in nodes {
            node.layer.removeAllAnimations()
        }
    }
    
    private func makeAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.toValue = 2
        animation.duration = indicatorAnimationDuration
        animation.autoreverses = true
        animation.repeatCount = .infinity
        return animation
    }
}

final class ContestCallControllerStatusNode: ASDisplayNode {
    private let titleNode: TextNode
    private let statusContainerNode: ASDisplayNode
    private let statusNode: TextNode
    private let statusMeasureNode: TextNode
    private let receptionNode: CallControllerReceptionNode
    private let logoNode: ASImageNode
    private let receptionTextStatusContainerNode: ASDisplayNode
    private let receptionTextNode: TextNode
    private let receptionEffectView: UIView
    private let indicator: ContestCallProgressIndicator
    
    private let titleActivateAreaNode: AccessibilityAreaNode
    private let statusActivateAreaNode: AccessibilityAreaNode
    
    var title: String = ""
    var subtitle: String = ""
    var status: CallControllerStatusValue = .text(string: "", displayLogo: false) {
        didSet {
            if self.status != oldValue {
                self.statusTimer?.invalidate()
                
                if let snapshotView = self.statusContainerNode.view.snapshotView(afterScreenUpdates: false) {
                    snapshotView.frame = self.statusContainerNode.frame
                    self.view.insertSubview(snapshotView, belowSubview: self.statusContainerNode.view)
                    
                    snapshotView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { [weak snapshotView] _ in
                        snapshotView?.removeFromSuperview()
                    })
                    snapshotView.layer.animateScale(from: 1.0, to: 0.3, duration: 0.3, removeOnCompletion: false)
                    snapshotView.layer.animatePosition(from: CGPoint(), to: CGPoint(x: 0.0, y: snapshotView.frame.height / 2.0), duration: 0.3, delay: 0.0, removeOnCompletion: false, additive: true)
                    
                    self.statusContainerNode.layer.animateScale(from: 0.3, to: 1.0, duration: 0.3)
                    self.statusContainerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
                    self.statusContainerNode.layer.animatePosition(from: CGPoint(x: 0.0, y: -snapshotView.frame.height / 2.0), to: CGPoint(), duration: 0.3, delay: 0.0, additive: true)
                }
                                
                if case .timer = self.status {
                    self.statusTimer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: { [weak self] in
                        if let strongSelf = self, let validLayoutWidth = strongSelf.validLayoutWidth {
                            let _ = strongSelf.updateLayout(constrainedWidth: validLayoutWidth, transition: .immediate)
                        }
                    }, queue: Queue.mainQueue())
                    self.statusTimer?.start()
                } else {
                    if let validLayoutWidth = self.validLayoutWidth {
                        let _ = self.updateLayout(constrainedWidth: validLayoutWidth, transition: .immediate)
                    }
                }
            }
        }
    }
    var reception: Int32? {
        didSet {
            if self.reception != oldValue {
                if let reception = self.reception {
                    self.receptionNode.reception = reception
                    
                    if oldValue == nil {
                        let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .spring)
                        transition.updateAlpha(node: self.receptionNode, alpha: 1.0)
                    }
                } else if self.reception == nil, oldValue != nil {
                    let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .spring)
                    transition.updateAlpha(node: self.receptionNode, alpha: 0.0)
                }
                
                if (oldValue == nil) != (self.reception != nil) {
                    if let validLayoutWidth = self.validLayoutWidth {
                        let _ = self.updateLayout(constrainedWidth: validLayoutWidth, transition: .immediate)
                    }
                }
            }
        }
    }

    private var statusTimer: SwiftSignalKit.Timer?
    private var validLayoutWidth: CGFloat?
    
    override init() {
        self.titleNode = TextNode()
        self.statusContainerNode = ASDisplayNode()
        self.statusNode = TextNode()
        self.statusNode.displaysAsynchronously = false
        self.statusMeasureNode = TextNode()
       
        self.receptionNode = CallControllerReceptionNode()
        self.receptionNode.alpha = 0.0
        
        self.logoNode = ASImageNode()
        self.logoNode.image = generateTintedImage(image: UIImage(bundleImageName: "Call/CallTitleLogo"), color: .white)
        self.logoNode.isHidden = true
        
        self.titleActivateAreaNode = AccessibilityAreaNode()
        self.titleActivateAreaNode.accessibilityTraits = .staticText
        
        self.statusActivateAreaNode = AccessibilityAreaNode()
        self.statusActivateAreaNode.accessibilityTraits = [.staticText, .updatesFrequently]
        
        self.indicator = ContestCallProgressIndicator()
        self.indicator.alpha = 0.0
        
        self.receptionTextStatusContainerNode = ASDisplayNode()
        self.receptionTextStatusContainerNode.alpha = 0.0
        self.receptionTextStatusContainerNode.clipsToBounds = true
        let receptionEffectView = UIVisualEffectView()
        receptionEffectView.effect = UIBlurEffect(style: .light)
        receptionEffectView.clipsToBounds = true
        receptionEffectView.isUserInteractionEnabled = false
        self.receptionEffectView = receptionEffectView
        self.receptionTextNode = TextNode()
        
        super.init()
        
        self.isUserInteractionEnabled = false
        
        self.addSubnode(self.titleNode)
        self.addSubnode(self.statusContainerNode)
        self.addSubnode(self.receptionTextStatusContainerNode)
        self.statusContainerNode.addSubnode(self.statusNode)
        self.statusContainerNode.addSubnode(self.receptionNode)
        self.statusContainerNode.addSubnode(self.logoNode)
        self.statusContainerNode.addSubnode(self.indicator)
        
        self.addSubnode(self.titleActivateAreaNode)
        self.addSubnode(self.statusActivateAreaNode)
        self.receptionTextStatusContainerNode.view.addSubview(self.receptionEffectView)
        self.receptionTextStatusContainerNode.addSubnode(self.receptionTextNode)
    }
    
    deinit {
        self.statusTimer?.invalidate()
    }
    
    func setVisible(_ visible: Bool, transition: ContainedViewLayoutTransition) {
        let alpha: CGFloat = visible ? 1.0 : 0.0
        transition.updateAlpha(node: self.titleNode, alpha: alpha)
        transition.updateAlpha(node: self.statusContainerNode, alpha: alpha)
    }
    
    func updateLayout(constrainedWidth: CGFloat, transition: ContainedViewLayoutTransition) -> CGFloat {
        self.validLayoutWidth = constrainedWidth
        
        let nameFont = regularNameFont
        let statusFont = regularStatusFont
        
        var statusOffset: CGFloat = 0.0
        let statusText: String
        let statusMeasureText: String
        var statusDisplayLogo: Bool = false
        var statusIndicator: Bool = false
        switch self.status {
        case .text(var text, let displayLogo):
            if displayLogo {
                statusOffset += 5
            } else if text.hasSuffix("...") {
                statusIndicator = true
                text.removeLast(3)
                statusOffset -= 8.0
            }
            statusText = text
            statusMeasureText = text
            statusDisplayLogo = displayLogo
            
        case let .timer(format, referenceTime):
            let duration = Int32(CFAbsoluteTimeGetCurrent() - referenceTime)
            let durationString: String
            let measureDurationString: String
            if duration > 60 * 60 {
                durationString = String(format: "%02d:%02d:%02d", arguments: [duration / 3600, (duration / 60) % 60, duration % 60])
                measureDurationString = "00:00:00"
            } else {
                durationString = String(format: "%02d:%02d", arguments: [(duration / 60) % 60, duration % 60])
                measureDurationString = "00:00"
            }
            statusText = format(durationString, false)
            statusMeasureText = format(measureDurationString, true)
            if self.reception != nil {
                statusOffset += 5.0
            }
        }
        
        let spacing: CGFloat = 1.0
        let (titleLayout, titleApply) = TextNode.asyncLayout(self.titleNode)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: self.title, font: nameFont, textColor: .white), backgroundColor: nil, maximumNumberOfLines: 1, truncationType: .end, constrainedSize: CGSize(width: constrainedWidth - 20.0, height: CGFloat.greatestFiniteMagnitude), alignment: .natural, cutout: nil, insets: UIEdgeInsets(top: 2.0, left: 2.0, bottom: 2.0, right: 2.0)))
        let (statusMeasureLayout, statusMeasureApply) = TextNode.asyncLayout(self.statusMeasureNode)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: statusMeasureText, font: statusFont, textColor: .white), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: CGSize(width: constrainedWidth - 20.0, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets(top: 2.0, left: 2.0, bottom: 2.0, right: 2.0)))
        let (statusLayout, statusApply) = TextNode.asyncLayout(self.statusNode)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: statusText, font: statusFont, textColor: .white), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: CGSize(width: constrainedWidth - 20.0, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets(top: 2.0, left: 2.0, bottom: 2.0, right: 2.0)))
        
        let weakNetworkText = "Weak network signal" // TODO: move to strings
        let (receptionLayout, receptionApply) = TextNode.asyncLayout(self.receptionTextNode)(TextNodeLayoutArguments(attributedString: NSAttributedString(string: weakNetworkText, font: regularReceptionFont, textColor: .white), backgroundColor: nil, maximumNumberOfLines: 0, truncationType: .end, constrainedSize: CGSize(width: constrainedWidth - 20.0, height: CGFloat.greatestFiniteMagnitude), alignment: .center, cutout: nil, insets: UIEdgeInsets(top: 2.0, left: 2.0, bottom: 2.0, right: 2.0)))

        let _ = titleApply()
        let _ = statusApply()
        let _ = statusMeasureApply()
        let _ = receptionApply()
        
        self.titleActivateAreaNode.accessibilityLabel = self.title
        self.statusActivateAreaNode.accessibilityLabel = statusText
        
        self.titleNode.frame = CGRect(origin: CGPoint(x: floor((constrainedWidth - titleLayout.size.width) / 2.0), y: 0.0), size: titleLayout.size)
        self.statusContainerNode.frame = CGRect(origin: CGPoint(x: 0.0, y: titleLayout.size.height + spacing), size: CGSize(width: constrainedWidth, height: statusLayout.size.height))
        self.statusNode.frame = CGRect(origin: CGPoint(x: floor((constrainedWidth - statusMeasureLayout.size.width) / 2.0) + statusOffset, y: 0.0), size: statusLayout.size)
        self.receptionNode.frame = CGRect(origin: CGPoint(x: self.statusNode.frame.minX - receptionNodeSize.width, y: 9.0), size: receptionNodeSize)
        self.logoNode.isHidden = !statusDisplayLogo
        if let image = self.logoNode.image, let firstLineRect = statusMeasureLayout.linesRects().first {
            let firstLineOffset = floor((statusMeasureLayout.size.width - firstLineRect.width) / 2.0)
            self.logoNode.frame = CGRect(origin: CGPoint(x: self.statusNode.frame.minX + firstLineOffset - image.size.width - 7.0, y: 5.0), size: image.size)
        }
        
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)
        if statusIndicator {
            self.indicator.frame = CGRect(origin: CGPoint(x: self.statusNode.frame.maxX + 8.0, y: self.statusNode.frame.midY - 1.0), size: self.indicator.size)
            transition.updateAlpha(node: self.indicator, alpha: 1.0)
            self.indicator.startAnimating()
        } else {
            transition.updateAlpha(node: self.indicator, alpha: 0.0)
            self.indicator.stopAnimating()
        }
        
        let receptionContainerSize = CGSize(width: receptionLayout.size.width + 24.0, height: receptionLayout.size.height + 10.0)
        let receptionContainerOrigin = CGPoint(x: (constrainedWidth - receptionContainerSize.width) / 2.0, y: self.statusContainerNode.frame.maxY + 12.0)
        self.receptionTextStatusContainerNode.frame = CGRect(origin: receptionContainerOrigin, size: receptionContainerSize)
        self.receptionTextNode.frame = CGRect(origin: CGPoint(x: 12, y: 5.0), size: receptionLayout.size)
        self.receptionEffectView.frame = self.receptionTextStatusContainerNode.bounds
        self.receptionTextStatusContainerNode.layer.cornerRadius = receptionContainerSize.height / 2.0
        
        self.titleActivateAreaNode.frame = self.titleNode.frame
        self.statusActivateAreaNode.frame = self.statusContainerNode.frame
        
        
        var receptionHeight = 0.0
        if (reception ?? 999) < 1 {
            transition.updateAlpha(node: self.receptionTextStatusContainerNode, alpha: 1.0)
            receptionHeight = 12.0 + receptionContainerSize.height
        } else {
            transition.updateAlpha(node: self.receptionTextStatusContainerNode, alpha: 0.0)
        }
        
        return titleLayout.size.height + spacing + statusLayout.size.height + receptionHeight
    }
}


private final class CallControllerReceptionNodeParameters: NSObject {
    let reception: Int32
    
    init(reception: Int32) {
        self.reception = reception
    }
}

private let receptionNodeSize = CGSize(width: 24.0, height: 10.0)
