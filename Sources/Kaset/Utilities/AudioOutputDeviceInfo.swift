import CoreAudio
import Foundation

/// Best-effort description of the system's current default audio output.
struct AudioOutputDeviceInfo: Equatable {
    let name: String
    let transportType: UInt32?

    static let unknown = AudioOutputDeviceInfo(name: String(localized: "Audio Output"), transportType: nil)

    var accessibilityName: String {
        self.name.isEmpty ? String(localized: "Audio Output") : self.name
    }

    func systemImageName(fallbackVolumeIcon: String) -> String {
        AudioOutputIconResolver.systemImageName(
            deviceName: self.name,
            transportType: self.transportType,
            fallbackVolumeIcon: fallbackVolumeIcon
        )
    }

    static func currentDefaultOutput() -> AudioOutputDeviceInfo {
        guard let deviceID = Self.defaultOutputDeviceID() else {
            return .unknown
        }

        return AudioOutputDeviceInfo(
            name: Self.deviceName(for: deviceID) ?? Self.unknown.name,
            transportType: Self.transportType(for: deviceID)
        )
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else {
            return nil
        }

        return deviceID
    }

    private static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let namePointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        namePointer.initialize(to: nil)
        defer {
            namePointer.deinitialize(count: 1)
            namePointer.deallocate()
        }
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            UnsafeMutableRawPointer(namePointer)
        )

        guard status == noErr, let name = namePointer.pointee else {
            return nil
        }

        return name as String
    }

    private static func transportType(for deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &transportType
        )

        guard status == noErr else {
            return nil
        }

        return transportType
    }
}

enum AudioOutputIconResolver {
    static func systemImageName(deviceName: String, transportType: UInt32?, fallbackVolumeIcon: String) -> String {
        let normalizedName = deviceName.localizedLowercase

        if normalizedName.contains("airpods") {
            return "airpods"
        }

        if transportType == kAudioDeviceTransportTypeAirPlay || normalizedName.contains("airplay") {
            return "airplayaudio"
        }

        if transportType == kAudioDeviceTransportTypeBluetooth
            || normalizedName.contains("beats")
            || normalizedName.contains("headphone")
            || normalizedName.contains("headset")
            || normalizedName.contains("earbud")
            || normalizedName.contains("buds")
        {
            return "headphones"
        }

        return fallbackVolumeIcon
    }
}
