import Foundation

/// Maps user-facing slider positions to output volume.
enum VolumeCurve {
    private static let exponent = 2.2

    static func outputVolume(forSliderValue sliderValue: Double) -> Double {
        pow(self.clamp(sliderValue), self.exponent)
    }

    static func sliderValue(forOutputVolume outputVolume: Double) -> Double {
        pow(self.clamp(outputVolume), 1.0 / self.exponent)
    }

    static func steppedOutputVolume(fromOutputVolume outputVolume: Double, bySliderStep sliderStep: Double) -> Double {
        let steppedSliderValue = self.sliderValue(forOutputVolume: outputVolume) + sliderStep
        return self.outputVolume(forSliderValue: steppedSliderValue)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
