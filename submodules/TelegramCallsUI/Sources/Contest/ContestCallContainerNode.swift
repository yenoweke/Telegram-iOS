import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import TelegramAudio
import AccountContext
import LocalizedPeerData
import PhotoResources
import CallsEmoji
import TooltipUI
import AlertUI
import PresentationDataUtils
import DeviceAccess
import ContextUI

private func log(_ what: @autoclosure () -> String) {
    Logger.shared.log("ContestCalls", what())
}

final class ContestCallContainerNode: ASDisplayNode, CallControllerNodeProtocol {
    
    private let presentationData: PresentationData

    private let containerNode: ASDisplayNode = ASDisplayNode()
    private let buttonsNode: ContestCallControllerButtonsNode = ContestCallControllerButtonsNode()
    
    private var expandedVideoNode: CallVideoNode?
    private var minimizedVideoNode: CallVideoNode?
    private var hasVideoNodes: Bool {
        return self.expandedVideoNode != nil || self.minimizedVideoNode != nil
    }
    
    var isMuted: Bool = false
    
    var toggleMute: (() -> Void)? {
        didSet {
            log("didSet toggleMute")
        }
    }
    
    var setCurrentAudioOutput: ((AudioSessionOutput) -> Void)? {
        didSet {
            log("didSet setCurrentAudioOutput")
        }
    }
    
    var beginAudioOuputSelection: ((Bool) -> Void)? {
        didSet {
            log("didSet beginAudioOuputSelection")
        }
    }
    
    var acceptCall: (() -> Void)? {
        didSet {
            log("didSet acceptCall")
        }
    }
    
    var endCall: (() -> Void)? {
        didSet {
            log("didSet endCall")
        }
    }
    
    var back: (() -> Void)? {
        didSet {
            log("didSet back")
        }
    }
    
    var presentCallRating: ((CallId, Bool) -> Void)? {
        didSet {
            log("didSet presentCallRating")
        }
    }
    
    var present: ((ViewController) -> Void)? {
        didSet {
            log("didSet present")
        }
    }
    
    var callEnded: ((Bool) -> Void)? {
        didSet {
            log("didSet callEnded")
        }
    }
    
    var dismissedInteractively: (() -> Void)? {
        didSet {
            log("didSet dismissedInteractively")
        }
    }
    
    var dismissAllTooltips: (() -> Void)? {
        didSet {
            log("didSet dismissAllTooltips")
        }
    }
    
    init(presentationData: PresentationData) {
        self.presentationData = presentationData
        log("initialized conatiner NODE")
        super.init()
        self.backgroundColor = .white
        self.setupNodes()
    }
    
    private func setupNodes() {
        self.addSubnode(self.containerNode)
        self.containerNode.addSubnode(self.buttonsNode)
        self.bindButtonNodes()
    }
    
    func bindButtonNodes() {
        self.buttonsNode.mute = { [weak self] in
            self?.toggleMute?()
            //TODO: Check in original what for
//            self?.cancelScheduledUIHiding()
        }
        
//        self.buttonsNode.speaker = { [weak self] in
//            guard let strongSelf = self else {
//                return
//            }
//            strongSelf.beginAudioOuputSelection?(strongSelf.hasVideoNodes)
//            strongSelf.cancelScheduledUIHiding()
//        }
    }
    
    override func layout() {
        super.layout()
        // TODO: check how "interpolateFrame(from: containerFullScreenFrame, to: containerPictureInPictureFrame" works
        self.containerNode.frame = self.bounds
    }
    
    func updateAudioOutputs(availableOutputs: [AudioSessionOutput], currentOutput: AudioSessionOutput?) {
        log("updateAudioOutputs")
    }
    
    func updateCallState(_ callState: PresentationCallState) {
        log("updateCallState, \(callState)")
    }
    
    func updatePeer(accountPeer: Peer, peer: Peer, hasOther: Bool) {
        log("updatePeer")
    }
    
    func animateIn() {
        log("animateIn")
    }
    
    func animateOut(completion: @escaping () -> Void) {
        log("animateOut")
    }
    
    func expandFromPipIfPossible() {
        log("expandFromPipIfPossible")
    }
    
    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        let buttonsMode: CallControllerButtonsMode = .outgoingRinging(speakerMode: .speaker, hasAudioRouteMenu: false, videoState: .init(isAvailable: true, isCameraActive: false, isScreencastActive: false, canChangeStatus: false, hasVideo: false, isInitializingCamera: false))
        let buttonsHeight = self.buttonsNode.updateLayout(strings: self.presentationData.strings, mode: buttonsMode, constrainedWidth: layout.size.width, bottomInset: layout.intrinsicInsets.bottom, transition: transition)
        
        let buttonsY = layout.size.height - layout.intrinsicInsets.bottom - 66.0 - buttonsHeight
        self.buttonsNode.frame = CGRect(x: 0.0, y: buttonsY, width: layout.size.width, height: buttonsHeight)
    }
    
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if self.containerNode.frame.contains(point) {
            return self.containerNode.view.hitTest(self.view.convert(point, to: self.containerNode.view), with: event)
        }
        return nil
    }
}
