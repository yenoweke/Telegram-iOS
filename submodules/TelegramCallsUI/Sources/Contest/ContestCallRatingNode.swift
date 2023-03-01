import Foundation
import UIKit
import SwiftSignalKit
import AsyncDisplayKit
import Display
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramVoip
import AccountContext
import AppBundle
import ComponentFlow

private let buttonCornerRadius: CGFloat = 14.0

final class ContestCallRatingNode: ASDisplayNode {
    private let strings: PresentationStrings
    private let apply: (Int) -> Void
    private let dismiss: () -> Void
    
    var rating: Int?
    
    private let contentNode: ASDisplayNode
    private let contentEffectView: UIVisualEffectView
    private let titleNode: ASTextNode
    private let subtitleNode: ASTextNode
    private var starContainerNode: ASDisplayNode
    private let starNodes: [ASButtonNode]
    
    private let actionNode: ASButtonNode
    
    private var lastImageSize: CGSize?
    private var lastImage: UIImage?
    private var validLayout: CGSize?
    
    init(strings: PresentationStrings, dismiss: @escaping () -> Void, apply: @escaping (Int) -> Void) {
        self.strings = strings
        self.apply = apply
        self.dismiss = dismiss
        
        self.contentNode = ASDisplayNode()
        self.contentNode.clipsToBounds = true
        self.contentNode.cornerRadius = 20.0
    
        if #available(iOS 13.0, *) {
            self.contentNode.layer.cornerCurve = .continuous
            self.contentEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
        } else {
            self.contentEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        }
        self.contentEffectView.alpha = 0.25
        
        self.titleNode = ASTextNode()

        self.subtitleNode = ASTextNode()
        self.subtitleNode.maximumNumberOfLines = 3
        
        self.starContainerNode = ASDisplayNode()
        
        var starNodes: [ASButtonNode] = []
        for _ in 0 ..< 5 {
            starNodes.append(ASButtonNode())
        }
        self.starNodes = starNodes
        
        self.actionNode = ASButtonNode()

        super.init()
        
        self.contentNode.view.addSubview(self.contentEffectView)
        self.contentNode.addSubnode(self.titleNode)
        self.contentNode.addSubnode(self.subtitleNode)
        self.contentNode.addSubnode(self.starContainerNode)
        
        for node in self.starNodes {
            node.addTarget(self, action: #selector(self.starPressed(_:)), forControlEvents: .touchDown)
            node.addTarget(self, action: #selector(self.starReleased(_:)), forControlEvents: .touchUpInside)
            self.starContainerNode.addSubnode(node)
        }
        self.actionNode.addTarget(self, action: #selector(self.actionPressed(_:)), forControlEvents: .touchUpInside)
        
        self.addSubnode(self.contentNode)
        self.addSubnode(self.actionNode)
        self.setup()
        self.starContainerNode.view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:))))
        
        self.contentNode.alpha = 0.0
        self.actionNode.alpha = 0.0
    }

    func animateIn(buttonFrom: CGRect?, buttonSnapshot: UIView?, transition: ContainedViewLayoutTransition) {
        guard let buttonFrom = buttonFrom, let buttonSnapshot = buttonSnapshot else {
            transition.updateAlpha(node: self.contentNode, alpha: 1.0)
            transition.updateAlpha(layer: self.actionNode.layer, alpha: 1.0)
            return
        }
    
        buttonSnapshot.frame = buttonFrom
        self.view.insertSubview(buttonSnapshot, belowSubview: self.actionNode.view)

        let backColor = UIColor(rgb: 0xff3b30)
        let expandingView = UIView()
        expandingView.backgroundColor = backColor
        expandingView.frame = buttonFrom
        expandingView.layer.cornerRadius = buttonFrom.height / 2.0
        self.view.insertSubview(expandingView, belowSubview: buttonSnapshot)

        transition.updateFrame(view: expandingView, frame: self.actionNode.frame)
        transition.updateCornerRadius(layer: expandingView.layer, cornerRadius: self.actionNode.cornerRadius)
        expandingView.layer.animate(from: backColor, to: UIColor.white.cgColor, keyPath: "backgroundColor", timingFunction: CAMediaTimingFunctionName.easeIn.rawValue, duration: 0.3)
        transition.updateAlpha(layer: expandingView.layer, alpha: 0.0, completion: { [weak expandingView] _ in
            expandingView?.removeFromSuperview()
        })
        transition.updateAlpha(layer: buttonSnapshot.layer, alpha: 0.0, completion: { [weak buttonSnapshot] _ in
            buttonSnapshot?.removeFromSuperview()
        })
    
        transition.updateAlpha(node: self.contentNode, alpha: 1.0)
        transition.animateTransformScale(node: self.contentNode, from: 0.7)
        
        transition.updateAlpha(node: self.actionNode, alpha: 1.0)
        
        let actionFrame = self.actionNode.frame
        let diffX = buttonFrom.maxX - actionFrame.maxX
        let diffY = actionFrame.minY - buttonFrom.minY
        let actionNodeFrameFrom = CGRect(x: actionFrame.minX - diffX, y: actionFrame.minY - diffY, width: actionFrame.width + 2 * diffX, height: actionFrame.height + 2 * diffY)
        
        ddlog("actionFrameOriginal \(actionFrame)")
        ddlog("actionNodeFrameFrom \(actionNodeFrameFrom) | \(diffX) | \(diffY)")

        let buttonMaskLayer = CAShapeLayer()
        buttonMaskLayer.fillColor = UIColor.black.cgColor
        let fromRect = self.view.convert(buttonFrom, to: self.actionNode.view)
        ddlog("UIBezierPath \(fromRect)")
        let fromPath = UIBezierPath(roundedRect: CGRect(origin: CGPoint(x: fromRect.origin.x + diffX, y: fromRect.origin.y + diffY), size: fromRect.size), cornerRadius: fromRect.height / 2.0)
        let toPath = UIBezierPath(roundedRect: CGRect(origin: CGPoint(x: self.actionNode.bounds.origin.x + diffX, y: self.actionNode.bounds.origin.y + diffY), size: self.actionNode.bounds.size), cornerRadius: buttonCornerRadius)
        buttonMaskLayer.path = fromPath.cgPath
        transition.updatePath(layer: buttonMaskLayer, path: toPath.cgPath)
        
        let image = makeActionTextImageIfNeeded(size: actionNodeFrameFrom.size)
        self.actionNode.setImage(image, for: .normal)
        self.actionNode.frame = actionNodeFrameFrom
//        transition.animateFrame(node: self.actionNode, from: actionNodeFrameFrom)

        self.actionNode.layer.opacity = 0.0
        self.actionNode.layer.cornerRadius = buttonFrom.height / 2.0
        self.actionNode.layer.mask = buttonMaskLayer

        transition.updateCornerRadius(layer: self.actionNode.layer, cornerRadius: buttonCornerRadius)
        transition.updateAlpha(layer: self.actionNode.layer, alpha: 1.0)
    }

    private func setup() {
        self.titleNode.attributedText = NSAttributedString(string: self.strings.Calls_ContestRatingTitle, font: Font.semibold(16.0), textColor: .white, paragraphAlignment: .center)
        
        self.subtitleNode.attributedText = NSAttributedString(string: self.strings.Calls_ContestRatingSubtitle, font: Font.regular(16.0), textColor: .white, paragraphAlignment: .center)

        for node in self.starNodes {
            node.setImage(generateTintedImage(image: UIImage(bundleImageName: "Call/ContestStar"), color: .white), for: [])
            let highlighted = generateTintedImage(image: UIImage(bundleImageName: "Call/ContestStarHighlighted"), color: .white)
            node.setImage(highlighted, for: [.selected])
            node.setImage(highlighted, for: [.selected, .highlighted])
        }

        self.actionNode.layer.cornerRadius = 10.0
        if #available(iOS 13.0, *) {
            self.actionNode.layer.cornerCurve = .continuous
        }
        self.actionNode.clipsToBounds = true
    }
    
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        var size = size
        size.width = min(size.width , 320.0)

        self.validLayout = size
        let actionButtonHeight: CGFloat = 50.0
        let contentSpacing: CGFloat = 10.0
        
        let contentInsets = UIEdgeInsets(top: 20.0, left: 20.0, bottom: 20.0, right: 20.0)
        
        let titleMaxWidth = size.width - contentInsets.left - contentInsets.right
        let titleSize = self.titleNode.measure(CGSize(width: titleMaxWidth, height: size.height))
        let titleOrigin = CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: contentInsets.top)
        let titleFrame = CGRect(origin: titleOrigin, size: titleSize)
        transition.updateFrame(node: self.titleNode, frame: titleFrame)
        
        let subtitleSize = self.subtitleNode.measure(CGSize(width: titleMaxWidth, height: size.height))
        let subtitleFrame = CGRect(origin: CGPoint(x: floor((size.width - subtitleSize.width) / 2.0), y: titleFrame.maxY + contentSpacing), size: subtitleSize)
        transition.updateFrame(node: self.subtitleNode, frame: subtitleFrame)
        
        let starSize = CGSize(width: 42.0, height: 42.0)
        let starsOriginX = floorToScreenPixels((size.width - starSize.width * 5.0) / 2.0)
        self.starContainerNode.frame = CGRect(origin: CGPoint(x: starsOriginX, y: subtitleFrame.maxY + contentSpacing), size: CGSize(width: starSize.width * CGFloat(self.starNodes.count), height: starSize.height))
        for i in 0 ..< self.starNodes.count {
            let node = self.starNodes[i]
            transition.updateFrame(node: node, frame: CGRect(x: starSize.width * CGFloat(i), y: 0.0, width: starSize.width, height: starSize.height))
        }

        let contentSize = CGSize(width: size.width, height: titleSize.height + contentSpacing + subtitleSize.height + contentSpacing + starSize.height + contentInsets.top + contentInsets.bottom)
        transition.updateFrame(node: self.contentNode, frame: CGRect(origin: .zero, size: contentSize))
        transition.updateFrame(view: self.contentEffectView, frame: CGRect(origin: .zero, size: contentSize))
        
        let spaceAfterContent: CGFloat = 66.0
        let actionNodeFrame = CGRect(origin: CGPoint(x: 0.0, y: contentSize.height + spaceAfterContent), size: CGSize(width: size.width, height: actionButtonHeight))
        transition.updateFrame(node: self.actionNode, frame: actionNodeFrame)
        self.actionNode.layer.cornerRadius = buttonCornerRadius
        self.actionNode.layer.mask = nil
        
        let image = makeActionTextImageIfNeeded(size: CGSize(width: self.actionNode.frame.size.width, height: self.actionNode.frame.size.height))
        if image !== self.actionNode.imageNode.image {
            self.actionNode.setImage(image, for: .normal)
        }

        return CGSize(width: size.width, height: contentSize.height + spaceAfterContent + actionNodeFrame.height)
    }
    
    @objc func panGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        let location = gestureRecognizer.location(in: self.starContainerNode.view)
        var selectedNode: ASButtonNode?
        for node in self.starNodes {
            if node.frame.contains(location) {
                selectedNode = node
                break
            }
        }
        if let selectedNode = selectedNode {
            switch gestureRecognizer.state {
                case .began, .changed:
                    self.starPressed(selectedNode)
                case .ended:
                    self.starReleased(selectedNode)
                case .cancelled:
                    self.resetStars()
                default:
                    break
            }
        } else {
            self.resetStars()
        }
    }
    
    private func resetStars() {
        for i in 0 ..< self.starNodes.count {
            let node = self.starNodes[i]
            node.isSelected = false
        }
    }
    
    @objc func starPressed(_ sender: ASButtonNode) {
        if let index = self.starNodes.firstIndex(of: sender) {
            self.rating = index + 1
            for i in 0 ..< self.starNodes.count {
                let node = self.starNodes[i]
                node.isSelected = i <= index
            }
        }
    }
    
    @objc func starReleased(_ sender: ASButtonNode) {
        if let index = self.starNodes.firstIndex(of: sender) {
            self.rating = index + 1
            for i in 0 ..< self.starNodes.count {
                let node = self.starNodes[i]
                node.isSelected = i <= index
            }
            if let rating = self.rating {
                self.apply(rating)
            }
        }
    }
    
    @objc func actionPressed(_ sender: ASButtonNode) {
        self.dismiss()
    }
    
    private func makeActionTextImageIfNeeded(size: CGSize) -> UIImage? {
        if self.lastImageSize == size, let lastImage = self.lastImage {
            return lastImage
        }
        
        ddlog("generating new image")
        self.lastImageSize = size
        self.lastImage = textTransparentImage(size: size, text: self.strings.Common_Close)
        return self.lastImage
    }
}

private func textTransparentImage(size: CGSize, text: String) -> UIImage? {
    UIGraphicsBeginImageContextWithOptions(size, true, 0)

    let context = UIGraphicsGetCurrentContext()
    context?.scaleBy(x: 1, y: -1)
    context?.translateBy(x: 0, y: -size.height)
    UIColor.white.setStroke()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: Font.semibold(17.0),
        .foregroundColor: UIColor.white
    ]
    let textSize = text.size(withAttributes: attributes)
    let point = CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2)
    text.draw(at: point, withAttributes: attributes)

    let maskImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    guard let cgimage = maskImage?.cgImage, let dataProvider = cgimage.dataProvider else { return nil }

    let bytesPerRow = cgimage.bytesPerRow
    let bitsPerPixel = cgimage.bitsPerPixel
    let width = cgimage.width
    let height = cgimage.height
    let bitsPerComponent = cgimage.bitsPerComponent

    guard let mask = CGImage(maskWidth: width, height: height, bitsPerComponent: bitsPerComponent, bitsPerPixel: bitsPerPixel, bytesPerRow: bytesPerRow, provider: dataProvider, decode: nil, shouldInterpolate: false) else { return nil }

    let rect = CGRect(origin: .zero, size: size)
    UIGraphicsBeginImageContextWithOptions(size, false, 0)
    UIGraphicsGetCurrentContext()?.clip(to: rect, mask: mask)
    UIColor.white.setFill()
    UIBezierPath(rect: rect).fill()
    let image = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()

    return image
}
