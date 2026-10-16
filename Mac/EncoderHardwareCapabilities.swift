import VideoToolbox

/// Query available encoders without starting capture or creating a virtual display.
enum EncoderHardwareCapabilities {
    static let hevc: Bool = {
        var list: CFArray?
        guard VTCopyVideoEncoderList(nil, &list) == noErr,
              let encoders = list as? [[String: Any]] else { return false }
        return encoders.contains {
            ($0[kVTVideoEncoderList_CodecType as String] as? NSNumber)?.uint32Value == kCMVideoCodecType_HEVC
                && ($0[kVTVideoEncoderList_IsHardwareAccelerated as String] as? Bool) == true
        }
    }()
}
