import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import AppBundle
import SemanticStatusNode
import AnimationUI

private let labelFont = Font.regular(13.0)

final class ContestCallButtonNode: HighlightTrackingButtonNode {
    
    private let wrapperNode: ASDisplayNode
    private let contentContainer: ASDisplayNode
    private let effectView: UIVisualEffectView
    private let overlayHighlightNode: ASImageNode
    private let contentNode: ASImageNode
    private let textNode: ImmediateTextNode
    
    private let largeButtonSize: CGFloat
    
    private(set) var currentContent: CallControllerButtonItemNode.Content?
    private(set) var currentText: String = ""
    
    init(largeButtonSize: CGFloat = 56.0) {
        self.largeButtonSize = largeButtonSize
        self.wrapperNode = ASDisplayNode()
        self.contentContainer = ASDisplayNode()
        
        self.effectView = UIVisualEffectView()
        self.effectView.effect = UIBlurEffect(style: .light)
        self.effectView.layer.cornerRadius = self.largeButtonSize / 2.0
        self.effectView.clipsToBounds = true
        self.effectView.isUserInteractionEnabled = false
        
        self.overlayHighlightNode = ASImageNode()
        self.overlayHighlightNode.isUserInteractionEnabled = false
        self.overlayHighlightNode.alpha = 0.0

        self.contentNode = ASImageNode()
        self.contentNode.isUserInteractionEnabled = false
        self.contentNode.clipsToBounds = true
        
        self.textNode = ImmediateTextNode()
        self.textNode.displaysAsynchronously = false
        self.textNode.isUserInteractionEnabled = false
        
        super.init(pointerStyle: nil)
        
        self.addSubnode(self.wrapperNode)
        self.wrapperNode.addSubnode(self.contentContainer)
        self.contentContainer.frame = CGRect(origin: CGPoint(), size: CGSize(width: self.largeButtonSize, height: self.largeButtonSize))
        
        self.wrapperNode.addSubnode(self.textNode)
        
        self.contentContainer.view.addSubview(self.effectView)
        self.contentContainer.addSubnode(self.contentNode)
        self.contentContainer.addSubnode(self.overlayHighlightNode)
        
        self.highligthedChanged = { [weak self] highlighted in
            guard let strongSelf = self else {
                return
            }
            if highlighted {
                strongSelf.overlayHighlightNode.alpha = 1.0
            } else {
                strongSelf.overlayHighlightNode.alpha = 0.0
                strongSelf.overlayHighlightNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
            }
        }
    }
    
    func update(text: String, content: CallControllerButtonItemNode.Content, transition: ContainedViewLayoutTransition) {
        let size = CGSize(width: self.largeButtonSize, height: self.largeButtonSize)
        let scaleFactor = size.width / self.largeButtonSize
        
        self.effectView.frame = CGRect(origin: CGPoint(), size: CGSize(width: self.largeButtonSize, height: self.largeButtonSize))
        self.contentNode.frame = CGRect(origin: CGPoint(), size: CGSize(width: self.largeButtonSize, height: self.largeButtonSize))
        self.overlayHighlightNode.frame = CGRect(origin: CGPoint(), size: CGSize(width: self.largeButtonSize, height: self.largeButtonSize))

        if self.currentContent != content {
            let previousContent = self.currentContent
            self.currentContent = content
            
            let contentImage = generateButtonContent(size: self.contentNode.frame.size, content: content)
            
            switch content.appearance {
            case .blurred:
                self.effectView.isHidden = false
            case .color:
                self.effectView.isHidden = true
            }
            
            transition.updateAlpha(node: self.wrapperNode, alpha: content.isEnabled ? 1.0 : 0.4)
            self.wrapperNode.isUserInteractionEnabled = content.isEnabled
            
            if transition.isAnimated, let contentImage = contentImage, let sourceContent = self.contentNode.image {
                
                let stageDuration: TimeInterval = 0.12
                
                if previousContent?.appearance.isFilled != content.appearance.isFilled {
                    let sourceNode = makeASImageNode(frame: self.contentNode.frame, image: sourceContent)
                    self.contentNode.addSubnode(sourceNode)
                    
                    let targetNode = makeASImageNode(frame: self.contentNode.frame, image: contentImage)
                    self.contentNode.addSubnode(targetNode)
                    
                    self.contentNode.image = contentImage
                    
                    let reversed = !content.appearance.isFilled
                    
                    hideNodeCircularLayer(reversed ? targetNode: sourceNode, duration: stageDuration, reversed: reversed, completion: { _ in})
                    animateCircleFill(reversed ? sourceNode: targetNode, duration: stageDuration, reversed: reversed, completion: { _ in
                        sourceNode.removeFromSupernode()
                        targetNode.removeFromSupernode()
                    })
                } else {
                    self.contentNode.image = contentImage
                    self.contentNode.layer.animate(from: sourceContent.cgImage!, to: contentImage.cgImage!, keyPath: "contents", timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, duration: 0.2)
                }
                
                animateScaling(transition: .animated(duration: stageDuration, curve: .spring))
                 
            } else {
                self.contentNode.image = contentImage
            }
            
            self.overlayHighlightNode.image = generateOverlayForButton(content.appearance, size: self.largeButtonSize)
        }
        
        transition.updatePosition(node: self.contentContainer, position: CGPoint(x: size.width / 2.0, y: size.height / 2.0))
        transition.updateSublayerTransformScale(node: self.contentContainer, scale: scaleFactor)
        
        if self.currentText != text {
            self.textNode.attributedText = NSAttributedString(string: text, font: labelFont, textColor: .white)
        }
        let textSize = self.textNode.updateLayout(CGSize(width: 150.0, height: 100.0))
        let textFrame = CGRect(origin: CGPoint(x: floor((size.width - textSize.width) / 2.0), y: size.height + 4.0), size: textSize)
        if self.currentText.isEmpty {
            self.textNode.frame = textFrame
            if transition.isAnimated {
                self.textNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.15)
            }
        } else {
            transition.updateFrameAdditiveToCenter(node: self.textNode, frame: textFrame)
        }
        self.currentText = text
    }

    private func hideNodeCircularLayer(_ node: ASDisplayNode, duration: TimeInterval, reversed: Bool, completion: @escaping (Bool) -> Void) {
        let center = node.frame.center
        let radius = node.frame.width / 2.0
        let layerMask = makeCircleLayer(lineWidth: 0.0, center: center, radius: radius, fillColor: .black)
        node.view.layer.mask = layerMask
        let fullFilledPath = UIBezierPath(arcCenter: center, radius: center.x, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true).cgPath
        let dotPath = UIBezierPath(arcCenter: center, radius: 0.01, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true).cgPath
        let from: CGPath = reversed ? dotPath : fullFilledPath
        let to: CGPath = reversed ? fullFilledPath : dotPath
        layerMask.animate(from: from, to: to, keyPath: "path", timingFunction: CAMediaTimingFunctionName.linear.rawValue, duration: duration, completion: completion)
    }
    
    private func animateCircleFill(_ node: ASDisplayNode, duration: TimeInterval, reversed: Bool, completion: @escaping (Bool) -> Void) {
        let center = node.frame.center
        let radius = node.frame.width / 2.0
        let from: CGFloat = reversed ? node.frame.width : 0.1
        let to: CGFloat = reversed ? 0.1 : node.frame.width
        let layerMask = makeCircleLayer(lineWidth: from, center: center, radius: radius, fillColor: .clear)
        node.view.layer.mask = layerMask

        layerMask.animate(from: from as NSNumber, to: to as NSNumber, keyPath: "lineWidth", timingFunction: CAMediaTimingFunctionName.linear.rawValue, duration: duration, completion: completion)
    }
    
    private func animateScaling(transition: ContainedViewLayoutTransition) {
        let transitionToScaleOrigin: (Bool) -> Void = { [weak self] result in
            guard result, let strongSelf = self else {
                return
            }
            transition.updateSublayerTransformScale(node: strongSelf, scale: 1.0)
        }
        
        let transitionToScaleUp: (Bool) -> Void = { [weak self] result in
            guard result, let strongSelf = self else {
                return
            }
            transition.updateSublayerTransformScale(node: strongSelf, scale: 1.08, completion: transitionToScaleOrigin)
        }
        transition.updateSublayerTransformScale(node: self, scale: 0.9, completion: transitionToScaleUp)
    }
    
    private func makeCircleLayer(lineWidth: CGFloat?, center: CGPoint, radius: CGFloat, fillColor: UIColor) -> CAShapeLayer {
        let circlePath = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: CGFloat(Double.pi * 2), clockwise: true)
        if let lineWidth = lineWidth {
            circlePath.lineWidth = lineWidth
        }
        
        let circleLayer = CAShapeLayer()
        circleLayer.path = circlePath.cgPath
        circleLayer.fillColor = fillColor.cgColor
        circleLayer.strokeColor = UIColor.black.cgColor
        if let lineWidth = lineWidth {
            circleLayer.lineWidth = lineWidth
        }
        return circleLayer
    }
    
    
    private func makeASImageNode(frame: CGRect, image: UIImage) -> ASImageNode {
        let imageNode = ASImageNode()
        imageNode.frame = frame
        imageNode.clipsToBounds = true
        imageNode.cornerRadius = frame.width / 2.0
        imageNode.image = image
        return imageNode
    }
}
