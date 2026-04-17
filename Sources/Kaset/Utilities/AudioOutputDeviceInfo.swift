import CoreAudio
import Foundation

/// Best-effort description of an available system audio output.
struct AudioOutputDeviceInfo: Equatable, Identifiable {
    let id: AudioDeviceID
    let name: String
    let transportType: UInt32?
    let manufacturer: String?
    let modelUID: String?

    static let unknown = AudioOutputDeviceInfo(
        id: AudioDeviceID(kAudioObjectUnknown),
        name: String(localized: "Audio Output"),
        transportType: nil,
        manufacturer: nil,
        modelUID: nil
    )

    init(
        id: AudioDeviceID = AudioDeviceID(kAudioObjectUnknown),
        name: String,
        transportType: UInt32?,
        manufacturer: String? = nil,
        modelUID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.transportType = transportType
        self.manufacturer = manufacturer
        self.modelUID = modelUID
    }

    var accessibilityName: String {
        self.name.isEmpty ? String(localized: "Audio Output") : self.name
    }

    var isSelectable: Bool {
        self.id != AudioDeviceID(kAudioObjectUnknown)
    }

    var isAirPods: Bool {
        AudioOutputIconResolver.isAirPods(
            deviceName: self.name,
            transportType: self.transportType,
            manufacturer: self.manufacturer,
            modelUID: self.modelUID
        )
    }

    var transportDescription: String {
        AudioOutputTransportDescription.name(for: self.transportType)
    }

    func systemImageName(fallbackVolumeIcon: String) -> String {
        AudioOutputIconResolver.systemImageName(
            deviceName: self.name,
            transportType: self.transportType,
            manufacturer: self.manufacturer,
            modelUID: self.modelUID,
            fallbackVolumeIcon: fallbackVolumeIcon
        )
    }

    func pickerButtonSystemImageName() -> String {
        AudioOutputIconResolver.pickerButtonSystemImageName(
            deviceName: self.name,
            transportType: self.transportType,
            manufacturer: self.manufacturer,
            modelUID: self.modelUID
        )
    }

    static func currentDefaultOutput() -> AudioOutputDeviceInfo {
        guard let deviceID = Self.defaultOutputDeviceID() else {
            return .unknown
        }

        return AudioOutputDeviceInfo(
            id: deviceID,
            name: Self.deviceName(for: deviceID) ?? Self.unknown.name,
            transportType: Self.transportType(for: deviceID),
            manufacturer: Self.manufacturer(for: deviceID),
            modelUID: Self.modelUID(for: deviceID)
        )
    }

    static func availableOutputDevices() -> [AudioOutputDeviceInfo] {
        Self.allDeviceIDs()
            .filter { Self.deviceHasOutputChannels($0) && Self.deviceIsAlive($0) }
            .map { deviceID in
                AudioOutputDeviceInfo(
                    id: deviceID,
                    name: Self.deviceName(for: deviceID) ?? String(localized: "Audio Output"),
                    transportType: Self.transportType(for: deviceID),
                    manufacturer: Self.manufacturer(for: deviceID),
                    modelUID: Self.modelUID(for: deviceID)
                )
            }
            .sorted { lhs, rhs in
                lhs.accessibilityName.localizedCaseInsensitiveCompare(rhs.accessibilityName) == .orderedAscending
            }
    }

    @discardableResult
    static func setDefaultOutput(_ output: AudioOutputDeviceInfo) -> Bool {
        guard output.isSelectable else { return false }

        let outputSet = Self.setDefaultDevice(output.id, selector: kAudioHardwarePropertyDefaultOutputDevice)
        _ = Self.setDefaultDevice(output.id, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        return outputSet
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard count > 0 else { return [] }

        var deviceIDs = [AudioDeviceID](repeating: AudioDeviceID(kAudioObjectUnknown), count: count)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            return []
        }

        return deviceIDs
    }

    private static func deviceHasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return false
        }

        let bufferListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer {
            bufferListPointer.deallocate()
        }

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            bufferListPointer
        )

        guard status == noErr else {
            return false
        }

        let audioBufferList = bufferListPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        return buffers.reduce(0) { channelCount, buffer in
            channelCount + Int(buffer.mNumberChannels)
        } > 0
    }

    private static func deviceIsAlive(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isAlive: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &isAlive
        )

        guard status == noErr else {
            return true
        }

        return isAlive != 0
    }

    private static func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var selectedDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectHasProperty(AudioObjectID(kAudioObjectSystemObject), &address) else {
            return false
        }

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            dataSize,
            &selectedDeviceID
        )

        return status == noErr
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
        Self.stringProperty(kAudioObjectPropertyName, for: deviceID)
    }

    private static func manufacturer(for deviceID: AudioDeviceID) -> String? {
        Self.stringProperty(kAudioObjectPropertyManufacturer, for: deviceID)
    }

    private static func modelUID(for deviceID: AudioDeviceID) -> String? {
        Self.stringProperty(kAudioDevicePropertyModelUID, for: deviceID)
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectHasProperty(deviceID, &address) else {
            return nil
        }

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
    static func pickerButtonSystemImageName(deviceName: String, transportType: UInt32?, manufacturer: String? = nil, modelUID: String? = nil) -> String {
        if Self.isAirPods(
            deviceName: deviceName,
            transportType: transportType,
            manufacturer: manufacturer,
            modelUID: modelUID
        ) {
            return "airpods"
        }

        return "hifispeaker"
    }

    static func systemImageName(
        deviceName: String,
        transportType: UInt32?,
        manufacturer: String? = nil,
        modelUID: String? = nil,
        fallbackVolumeIcon: String
    ) -> String {
        let normalizedName = deviceName.localizedLowercase

        if Self.isAirPods(
            deviceName: deviceName,
            transportType: transportType,
            manufacturer: manufacturer,
            modelUID: modelUID
        ) {
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

    static func isAirPods(deviceName: String, transportType: UInt32?, manufacturer: String? = nil, modelUID: String? = nil) -> Bool {
        let normalizedName = deviceName.localizedLowercase
        let normalizedManufacturer = manufacturer?.localizedLowercase ?? ""
        let normalizedModelUID = modelUID?.localizedLowercase ?? ""

        if normalizedName.contains("beats") || normalizedModelUID.contains("beats") {
            return false
        }

        if normalizedName.contains("airpods") || normalizedModelUID.contains("airpods") {
            return true
        }

        return transportType == kAudioDeviceTransportTypeBluetooth
            && normalizedManufacturer.contains("apple")
    }
}

private enum AudioOutputTransportDescription {
    static func name(for transportType: UInt32?) -> String {
        switch transportType {
        case kAudioDeviceTransportTypeBuiltIn:
            return String(localized: "Built-In")
        case kAudioDeviceTransportTypeBluetooth:
            return String(localized: "Bluetooth")
        case kAudioDeviceTransportTypeBluetoothLE:
            return String(localized: "Bluetooth")
        case kAudioDeviceTransportTypeAirPlay:
            return String(localized: "AirPlay")
        case kAudioDeviceTransportTypeUSB:
            return String(localized: "USB")
        case kAudioDeviceTransportTypeHDMI:
            return String(localized: "HDMI")
        case kAudioDeviceTransportTypeDisplayPort:
            return String(localized: "DisplayPort")
        case kAudioDeviceTransportTypeAggregate:
            return String(localized: "Aggregate Device")
        case kAudioDeviceTransportTypeVirtual:
            return String(localized: "Virtual Device")
        default:
            return String(localized: "Output Device")
        }
    }
}
