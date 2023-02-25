import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import LegacyComponents

private let emojiFont = Font.regular(38.0)
private let titleFont = Font.semibold(16.0)
private let textFont = Font.regular(16.0)
private let buttonFont = Font.regular(20.0)

final class ContestCallControllerKeyPreviewNode: ASDisplayNode {
    private let keyTextNode: ASTextNode
    private let titleTextNode: ASTextNode
    private let infoTextNode: ASTextNode
    private let buttonTextNode: ASTextNode
    
    private let topEffectView: UIVisualEffectView
    private let separatorView: UIView
    private let containerNode: ASDisplayNode
    
    private let dismiss: () -> Void
    private var animateOutInProgress = false
    private var light: Bool?
    
    init(keyText: String, titleText: String, infoText: String, buttonText: String, light: Bool, dismiss: @escaping () -> Void) {
        self.keyTextNode = ASTextNode()
        self.keyTextNode.displaysAsynchronously = false
        self.titleTextNode = ASTextNode()
        self.titleTextNode.displaysAsynchronously = false
        self.infoTextNode = ASTextNode()
        self.infoTextNode.displaysAsynchronously = false
        self.buttonTextNode = ASTextNode()
        self.buttonTextNode.displaysAsynchronously = false
        self.dismiss = dismiss
        
        self.containerNode = ASDisplayNode()
        self.topEffectView = UIVisualEffectView()
        self.separatorView = UIView()
        self.separatorView.backgroundColor = .white
        self.separatorView.alpha = 0.33

        super.init()
        
        self.keyTextNode.attributedText = NSAttributedString(string: keyText, attributes: [NSAttributedString.Key.font: emojiFont, NSAttributedString.Key.kern: 6.0 as NSNumber])
        
        self.titleTextNode.attributedText = NSAttributedString(string: titleText, font: titleFont, textColor: UIColor.white, paragraphAlignment: .center)
        
        self.infoTextNode.attributedText = NSAttributedString(string: infoText, font: textFont, textColor: UIColor.white, paragraphAlignment: .center)

        self.buttonTextNode.attributedText = NSAttributedString(string: buttonText, font: buttonFont, textColor: UIColor.white, paragraphAlignment: .center)
        
        self.containerNode.view.addSubview(self.topEffectView)
        self.containerNode.view.addSubview(self.separatorView)
        self.containerNode.addSubnode(self.titleTextNode)
        self.containerNode.addSubnode(self.infoTextNode)
        self.containerNode.addSubnode(self.buttonTextNode)
        self.addSubnode(self.containerNode)
        self.addSubnode(self.keyTextNode)

        self.containerNode.layer.cornerRadius = 16.0
        self.containerNode.clipsToBounds = true
        if #available(iOS 13.0, *) {
            self.containerNode.layer.cornerCurve = .continuous
        }
        self.updateAppearance(light: light)
    }
    
    func updateAppearance(light: Bool) {
        if self.light == light {
            return
        }
        self.light = light
        let blurStyle: UIBlurEffect.Style
        if #available(iOS 13.0, *) {
            blurStyle = light ? .systemMaterialLight : .systemMaterialDark
        } else {
            blurStyle = light ? .light : .dark
        }
        self.topEffectView.effect = UIBlurEffect(style: blurStyle)
        self.topEffectView.alpha = light ? 0.25 : 1.0
    }
    
    override func didLoad() {
        super.didLoad()
        
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        if animateOutInProgress { return .zero }

        let maxWidth = size.width - 90.0
        
        let keyTopOffset: CGFloat = 20.0
        let keyTextSize = self.keyTextNode.measure(CGSize(width: maxWidth, height: 300.0))
        let keyTextFrame = CGRect(origin: CGPoint(x: floor((maxWidth - keyTextSize.width) / 2), y: keyTopOffset), size: keyTextSize)
        transition.updateFrame(node: self.keyTextNode, frame: keyTextFrame)
        
        let titleTextSize = self.titleTextNode.measure(CGSize(width: maxWidth - 16.0 * 2.0, height: CGFloat.greatestFiniteMagnitude))
        let titleTextFrame = CGRect(origin: CGPoint(x: floor((maxWidth - titleTextSize.width) / 2.0), y: keyTextFrame.maxY + 10.0), size: titleTextSize)
        transition.updateFrame(node: self.titleTextNode, frame: titleTextFrame)
        
        let infoTextSize = self.infoTextNode.measure(CGSize(width: maxWidth - 16.0 * 2.0, height: CGFloat.greatestFiniteMagnitude))
        let infoTextFrame = CGRect(origin: CGPoint(x: floor((maxWidth - infoTextSize.width) / 2.0), y: titleTextFrame.maxY + 10.0), size: infoTextSize)
        transition.updateFrame(node: self.infoTextNode, frame: infoTextFrame)
        
        let topSize = CGSize(width: maxWidth, height: infoTextFrame.maxY + 18.0)
        self.topEffectView.frame = CGRect(origin: .zero, size: topSize)
        
        self.separatorView.frame = CGRect(origin: CGPoint(x: 0.0, y: self.topEffectView.frame.maxY), size: CGSize(width: maxWidth, height: 1.0))

        let buttonTextSize = self.buttonTextNode.measure(CGSize(width: maxWidth - 16.0 * 2.0, height: CGFloat.greatestFiniteMagnitude))
        self.buttonTextNode.frame.size = buttonTextSize
        self.buttonTextNode.layer.position = CGPoint(x: self.separatorView.frame.midX, y: self.separatorView.frame.maxY + 16.0 + buttonTextSize.height / 2.0)
        let finalSize = CGSize(width: maxWidth, height: self.buttonTextNode.frame.maxY + 16.0)
        self.topEffectView.frame = CGRect(origin: .zero, size: finalSize)
        return finalSize
    }
    
    func animateIn(from rect: CGRect, fromNode: ASDisplayNode, parentNode: ASDisplayNode) {
        self.containerNode.frame.size = self.bounds.size
        self.containerNode.frame.origin = .zero
        self.containerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        let scaleFactor: CGFloat = 0.7
        let keyAnimationDuration: TimeInterval = 0.3
        // TODO: add small spring animation
        self.containerNode.layer.animateScale(from: scaleFactor, to: 1.0, duration: keyAnimationDuration)
        
        var containerFromPosition = self.containerNode.layer.position
        let containerOffsetX = self.containerNode.frame.width * (1.0 - scaleFactor) / 2.0
        let containerOffsetY = self.containerNode.frame.height * (1.0 - scaleFactor) / 2.0
        containerFromPosition.x += containerOffsetX
        containerFromPosition.y -= containerOffsetY
        self.containerNode.layer.animatePosition(from: containerFromPosition, to: self.containerNode.layer.position, duration: keyAnimationDuration)

        let keyAnimateFrom = self.convert(CGPoint(x: rect.midX, y: rect.midY), from: parentNode)
        let keyAnimateTo = self.keyTextNode.layer.position
        let keyPositionPath = makeInPath(startPoint: keyAnimateFrom, endPoint: keyAnimateTo)
        self.keyTextNode.layer.animateKeyframe(cgPath: keyPositionPath, duration: keyAnimationDuration, keyPath: "position", mediaTimingFunction: CAMediaTimingFunction(name: .easeOut))

        if let transitionView = fromNode.view.snapshotView(afterScreenUpdates: false) {
            self.view.addSubview(transitionView)
            transitionView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false)
            transitionView.layer.animateKeyframe(cgPath: keyPositionPath, duration: keyAnimationDuration, keyPath: "position", mediaTimingFunction: CAMediaTimingFunction(name: .easeOut))

            transitionView.layer.animateScale(from: 1.0, to: self.keyTextNode.frame.size.width / rect.size.width, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        }
        self.keyTextNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15, removeOnCompletion: false)
        self.keyTextNode.layer.animateScale(from: rect.size.width / self.keyTextNode.frame.size.width, to: 1.0, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring)
    }
    
    func animateOut(to rect: CGRect, toNode: ASDisplayNode, parentNode: ASDisplayNode, completion: @escaping () -> Void) {
        let keyAnimateTo = self.convert(CGPoint(x: rect.midX + 2.0, y: rect.midY), from: parentNode)
        let keyAnimateFrom = self.keyTextNode.layer.position
        let path = makeOutPath(startPoint: keyAnimateFrom, endPoint: keyAnimateTo)
        self.keyTextNode.layer.position = keyAnimateTo
        self.keyTextNode.layer.animateKeyframe(cgPath: path, duration: 0.3, keyPath: "position", mediaTimingFunction: CAMediaTimingFunction(name: .easeOut), removeOnCompletion: false, completion: {_ in
            completion()
        })
        
        self.keyTextNode.layer.animateScale(from: 1.0, to: rect.size.width / (self.keyTextNode.frame.size.width - 2.0), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)

        let scaleFactor: CGFloat = 0.7
        let duration: TimeInterval = 0.12
        var containerToPosition = self.containerNode.layer.position
        let containerOffsetX = self.containerNode.frame.width * (1.0 - scaleFactor) / 2.0
        let containerOffsetY = self.containerNode.frame.height * (1.0 - scaleFactor) / 2.0
        containerToPosition.x += containerOffsetX
        containerToPosition.y -= containerOffsetY
        self.containerNode.layer.animatePosition(from: self.containerNode.layer.position, to: containerToPosition, duration: duration, timingFunction: CAMediaTimingFunctionName.linear.rawValue, removeOnCompletion: false)
        self.containerNode.layer.animateScale(from: 1.0, to: scaleFactor, duration: duration, timingFunction: CAMediaTimingFunctionName.linear.rawValue, removeOnCompletion: false)
        self.containerNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: duration, timingFunction: CAMediaTimingFunctionName.linear.rawValue, removeOnCompletion: false)
    }
    
    @objc func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.dismiss()
        }
    }
    
}

private func makeInPath(startPoint: CGPoint, endPoint: CGPoint) -> CGPath {
    let path = UIBezierPath()
    path.move(to: startPoint)
    let diffX = (startPoint.x + endPoint.x) * 0.17
    let diffY = (startPoint.y + endPoint.y) * 0.17
    let controlPoint1 = CGPoint(x: startPoint.x, y: endPoint.y - diffY)
    let controlPoint2 = CGPoint(x: startPoint.x - diffX, y: endPoint.y)
    path.addCurve(
        to: endPoint,
        controlPoint1: controlPoint1,
        controlPoint2: controlPoint2
    )
    return path.cgPath
}

private func makeOutPath(startPoint: CGPoint, endPoint: CGPoint) -> CGPath {
    let path = UIBezierPath()
    path.move(to: startPoint)
    let diffX = (startPoint.x + endPoint.x) * 0.17
    let diffY = (startPoint.y + endPoint.y) * 0.17
    let controlPoint1 = CGPoint(x: endPoint.x - diffX, y: startPoint.y)
    let controlPoint2 = CGPoint(x: endPoint.x, y: startPoint.y - diffY)
    path.addCurve(
        to: endPoint,
        controlPoint1: controlPoint1,
        controlPoint2: controlPoint2
    )
    return path.cgPath
}
