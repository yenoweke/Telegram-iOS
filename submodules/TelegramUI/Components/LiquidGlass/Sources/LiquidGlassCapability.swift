import Foundation
import DeviceModel

public enum LiquidGlassCapability {
    public static var isDeviceSupported: Bool {
        switch DeviceModel.current {
        case .iPodTouch1, .iPodTouch2, .iPodTouch3, .iPodTouch4, .iPodTouch5, .iPodTouch6, .iPodTouch7,
             .iPhone, .iPhone3G, .iPhone3GS,
             .iPhone4, .iPhone4S,
             .iPhone5, .iPhone5C, .iPhone5S,
             .iPhone6, .iPhone6Plus, .iPhone6S, .iPhone6SPlus,
             .iPhoneSE,
             .iPhone7, .iPhone7Plus,
             .iPhone8, .iPhone8Plus,
             .iPhoneX, .iPhoneXS, .iPhoneXSMax, .iPhoneXR:
            return false
        default:
            return true
        }
    }
}
