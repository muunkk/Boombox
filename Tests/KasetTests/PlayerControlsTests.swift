import Testing
@testable import Kaset

@Suite(.tags(.model))
struct PlayerControlsTests {
    @Test("Volume curve clamps endpoints")
    func volumeCurveClampsEndpoints() {
        #expect(VolumeCurve.outputVolume(forSliderValue: -0.4) == 0)
        #expect(VolumeCurve.outputVolume(forSliderValue: 1.4) == 1)
        #expect(VolumeCurve.sliderValue(forOutputVolume: -0.4) == 0)
        #expect(VolumeCurve.sliderValue(forOutputVolume: 1.4) == 1)
    }

    @Test("Volume curve gives low slider values finer output control")
    func volumeCurveGivesLowSliderValuesFinerOutputControl() {
        #expect(VolumeCurve.outputVolume(forSliderValue: 0.25) < 0.1)
        #expect(VolumeCurve.outputVolume(forSliderValue: 0.5) < 0.5)
        #expect(VolumeCurve.outputVolume(forSliderValue: 0.9) > 0.75)
    }

    @Test("Volume curve round trips representative values")
    func volumeCurveRoundTripsRepresentativeValues() {
        for value in [0.0, 0.01, 0.1, 0.33, 0.5, 0.75, 1.0] {
            let sliderValue = VolumeCurve.sliderValue(forOutputVolume: value)
            let outputVolume = VolumeCurve.outputVolume(forSliderValue: sliderValue)
            #expect(abs(outputVolume - value) < 0.000001)
        }
    }

    @Test("Audio output icon resolver recognizes common devices")
    func audioOutputIconResolverRecognizesCommonDevices() {
        #expect(AudioOutputIconResolver.systemImageName(deviceName: "Mel's AirPods Pro", transportType: nil, fallbackVolumeIcon: "speaker.wave.2.fill") == "airpods")
        #expect(AudioOutputIconResolver.systemImageName(deviceName: "Living Room AirPlay", transportType: nil, fallbackVolumeIcon: "speaker.wave.2.fill") == "airplayaudio")
        #expect(AudioOutputIconResolver.systemImageName(deviceName: "Bluetooth Headphones", transportType: nil, fallbackVolumeIcon: "speaker.wave.2.fill") == "headphones")
        #expect(AudioOutputIconResolver.systemImageName(deviceName: "MacBook Pro Speakers", transportType: nil, fallbackVolumeIcon: "speaker.wave.2.fill") == "speaker.wave.2.fill")
    }

    @Test("Audio output picker button uses speaker icon unless AirPods are active")
    func audioOutputPickerButtonUsesSpeakerIconUnlessAirPodsAreActive() {
        #expect(AudioOutputIconResolver.pickerButtonSystemImageName(deviceName: "MacBook Pro Speakers", transportType: nil) == "hifispeaker")
        #expect(AudioOutputIconResolver.pickerButtonSystemImageName(deviceName: "Studio Display Speakers", transportType: nil) == "hifispeaker")
        #expect(AudioOutputIconResolver.pickerButtonSystemImageName(deviceName: "Mel's AirPods Pro", transportType: nil) == "airpods")
    }
}
