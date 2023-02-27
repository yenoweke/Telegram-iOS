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

func ddlog(_ what: @autoclosure () -> String) {
    Logger.shared.log("ContestCalls", what())
}

//final class ContestCallContainerNode: ASDisplayNode, CallControllerNodeProtocol {
//
//    private let presentationData: PresentationData
//
//    private let containerNode: ASDisplayNode = ASDisplayNode()
//    private let buttonsNode: ContestCallControllerButtonsNode = ContestCallControllerButtonsNode()
//
//    private var expandedVideoNode: CallVideoNode?
//    private var minimizedVideoNode: CallVideoNode?
//    private var hasVideoNodes: Bool {
//        return self.expandedVideoNode != nil || self.minimizedVideoNode != nil
//    }
//
//    var isMuted: Bool = false
//
//    var toggleMute: (() -> Void)? {
//        didSet {
//            ddlog("didSet toggleMute")
//        }
//    }
//
//    var setCurrentAudioOutput: ((AudioSessionOutput) -> Void)? {
//        didSet {
//            ddlog("didSet setCurrentAudioOutput")
//        }
//    }
//
//    var beginAudioOuputSelection: ((Bool) -> Void)? {
//        didSet {
//            ddlog("didSet beginAudioOuputSelection")
//        }
//    }
//
//    var acceptCall: (() -> Void)? {
//        didSet {
//            ddlog("didSet acceptCall")
//        }
//    }
//
//    var endCall: (() -> Void)? {
//        didSet {
//            ddlog("didSet endCall")
//        }
//    }
//
//    var back: (() -> Void)? {
//        didSet {
//            ddlog("didSet back")
//        }
//    }
//
//    var presentCallRating: ((CallId, Bool) -> Void)? {
//        didSet {
//            ddlog("didSet presentCallRating")
//        }
//    }
//
//    var present: ((ViewController) -> Void)? {
//        didSet {
//            ddlog("didSet present")
//        }
//    }
//
//    var callEnded: ((Bool) -> Void)? {
//        didSet {
//            ddlog("didSet callEnded")
//        }
//    }
//
//    var dismissedInteractively: (() -> Void)? {
//        didSet {
//            ddlog("didSet dismissedInteractively")
//        }
//    }
//
//    var dismissAllTooltips: (() -> Void)? {
//        didSet {
//            ddlog("didSet dismissAllTooltips")
//        }
//    }
//
//    init(presentationData: PresentationData) {
//        self.presentationData = presentationData
//        ddlog("initialized conatiner NODE")
//        super.init()
//        self.backgroundColor = .white
//        self.setupNodes()
//    }
//
//    private func setupNodes() {
//        self.addSubnode(self.containerNode)
//        self.containerNode.addSubnode(self.buttonsNode)
//        self.bindButtonNodes()
//    }
//
//    func bindButtonNodes() {
//        self.buttonsNode.mute = { [weak self] in
//            self?.toggleMute?()
//            //TODO: Check in original what for
////            self?.cancelScheduledUIHiding()
//        }
//
////        self.buttonsNode.speaker = { [weak self] in
////            guard let strongSelf = self else {
////                return
////            }
////            strongSelf.beginAudioOuputSelection?(strongSelf.hasVideoNodes)
////            strongSelf.cancelScheduledUIHiding()
////        }
//    }
//
//    override func layout() {
//        super.layout()
//        // TODO: check how "interpolateFrame(from: containerFullScreenFrame, to: containerPictureInPictureFrame" works
//        self.containerNode.frame = self.bounds
//    }
//
//    func updateAudioOutputs(availableOutputs: [AudioSessionOutput], currentOutput: AudioSessionOutput?) {
//        ddlog("updateAudioOutputs")
//    }
//
//    func updateCallState(_ callState: PresentationCallState) {
//        ddlog("updateCallState, \(callState)")
//    }
//
//    func updatePeer(accountPeer: Peer, peer: Peer, hasOther: Bool) {
//        ddlog("updatePeer")
//    }
//
//    func animateIn() {
//        ddlog("animateIn")
//    }
//
//    func animateOut(completion: @escaping () -> Void) {
//        ddlog("animateOut")
//    }
//
//    func expandFromPipIfPossible() {
//        ddlog("expandFromPipIfPossible")
//    }
//
//    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
//        let buttonsMode: CallControllerButtonsMode = .outgoingRinging(speakerMode: .speaker, hasAudioRouteMenu: false, videoState: .init(isAvailable: true, isCameraActive: false, isScreencastActive: false, canChangeStatus: false, hasVideo: false, isInitializingCamera: false))
//        let buttonsHeight = self.buttonsNode.updateLayout(strings: self.presentationData.strings, mode: buttonsMode, constrainedWidth: layout.size.width, bottomInset: layout.intrinsicInsets.bottom, transition: transition)
//
//        let buttonsY = layout.size.height - layout.intrinsicInsets.bottom - 66.0 - buttonsHeight
//        self.buttonsNode.frame = CGRect(x: 0.0, y: buttonsY, width: layout.size.width, height: buttonsHeight)
//    }
//
//
//    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
//        if self.containerNode.frame.contains(point) {
//            return self.containerNode.view.hitTest(self.view.convert(point, to: self.containerNode.view), with: event)
//        }
//        return nil
//    }
//}
