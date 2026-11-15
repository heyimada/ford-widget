import Foundation

extension Locale {
    var usesMetricPressure: Bool { measurementSystem == .metric }
}

enum Format {
    /// Bar for metric locales, psi otherwise.
    static func pressure(kPa: Double, locale: Locale) -> String {
        let measurement = Measurement(value: kPa, unit: UnitPressure.kilopascals)
        if locale.usesMetricPressure {
            return measurement.converted(to: .bars).formatted(
                .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2)).locale(locale)).locale(locale))
        }
        return measurement.converted(to: .poundsForcePerSquareInch).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)).locale(locale)).locale(locale))
    }

    static func temperature(celsius: Double, locale: Locale) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius).formatted(
            .measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)).locale(locale)).locale(locale))
    }

    static func percent(_ value: Int) -> String { "\(value) %" }

    static func ago(_ date: Date, now: Date = Date(), locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = locale
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func maskedVIN(_ vin: String) -> String {
        String(repeating: "•", count: max(0, vin.count - 6)) + vin.suffix(6)
    }
}
