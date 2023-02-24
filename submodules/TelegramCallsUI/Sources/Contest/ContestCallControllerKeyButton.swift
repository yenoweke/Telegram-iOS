import Foundation
import UIKit
import Display
import AsyncDisplayKit
import CallsEmoji

private let labelFont = Font.regular(24.0)

private class EmojiNode: ASDisplayNode {
    var emoji: String = "" {
        didSet {
            self.node.attributedText = NSAttributedString(string: emoji, font: labelFont, textColor: .black)
            let _ = self.node.updateLayout(CGSize(width: 100.0, height: 100.0))
        }
    }
    
    private let containerNode: ASDisplayNode
    private let node: ImmediateTextNode

    override init() {
        self.containerNode = ASDisplayNode()
        self.node = ImmediateTextNode()
        
        super.init()

        self.addSubnode(self.containerNode)
        self.containerNode.addSubnode(self.node)
    }
    
    override func layout() {
        super.layout()
        let containerSize = CGSize(width: self.bounds.width, height: self.bounds.height)
        self.containerNode.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: containerSize)
        self.node.frame = CGRect(origin: CGPoint(), size: self.bounds.size)
    }
}

final class ContestCallControllerKeyButton: HighlightableButtonNode {
    private let containerNode: ASDisplayNode
    private let nodes: [EmojiNode]
    
    var key: String = "" {
        didSet {
            var index = 0
            for emoji in self.key {
                guard index < 4 else {
                    return
                }
                self.nodes[index].emoji = String(emoji)
                index += 1
            }
        }
    }
    
    init() {
        self.containerNode = ASDisplayNode()
        self.nodes = (0 ..< 4).map { _ in EmojiNode() }
       
        super.init(pointerStyle: nil)
        
        self.addSubnode(self.containerNode)
        self.nodes.forEach({ self.containerNode.addSubnode($0) })
    }
        
    func animateIn() {
        self.layoutIfNeeded()
        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)
        var idx = nodes.count
        for node in self.nodes {
            var from = node.frame
            from.origin.x -= CGFloat(idx * 20)
            transition.animateFrame(node: node, from: from, to: node.frame)
            idx -= 1
        }

        self.containerNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }
    
    override func measure(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: 114.0, height: 26.0)
    }
    
    override func layout() {
        super.layout()
        
        self.containerNode.frame = self.bounds
        var index = 0
        let nodeSize = CGSize(width: 29.0, height: self.bounds.size.height)
        for node in self.nodes {
            node.frame = CGRect(origin: CGPoint(x: CGFloat(index) * nodeSize.width, y: 0.0), size: nodeSize)
            index += 1
        }
        self.nodes.forEach({ self.containerNode.addSubnode($0) })
    }
}
