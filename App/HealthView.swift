import SwiftUI

struct HealthView: View {
    @Bindable var model: AppModel
    @Environment(\.locale) private var locale

    private var details: VehicleDetails? { model.snapshot?.details }

    var body: some View {
        List {
            tires
            oil
            battery
            coolant
            warnings
        }
        .refreshable { await model.refresh() }
        .navigationTitle("Health")
        .toolbar { CarToolbar(model: model) }
    }

    private var tires: some View {
        Section("Tires") {
            if let tires = details?.tires, !tires.isEmpty {
                ForEach(tires, id: \.wheel) { tire in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tire.wheel.title)
                            if let placard = tire.placardKPa {
                                Text("Recommended \(Format.pressure(kPa: placard, locale: locale))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(tire.pressureKPa.map { Format.pressure(kPa: $0, locale: locale) } ?? "–")
                            .monospacedDigit()
                        statusIcon(tire.status)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text("Unknown").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func statusIcon(_ status: TireStatus) -> some View {
        switch status {
        case .normal: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Normal")
        case .low: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityLabel("Low")
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary).accessibilityLabel("Unknown")
        }
    }

    private var oil: some View {
        Section("Oil life") {
            if let oil = details?.oilLifePercent {
                Gauge(value: Double(min(max(oil, 0), 100)), in: 0...100) {
                    Text("Oil life")
                } currentValueLabel: {
                    Text(Format.percent(oil))
                }
                .gaugeStyle(.linearCapacity)
                .tint(oil < 15 ? .red : oil < 30 ? .orange : .green)
            } else {
                Text("Unknown").foregroundStyle(.secondary)
            }
        }
    }

    private var battery: some View {
        Section("12V battery") {
            if let percent = details?.batteryPercent {
                Gauge(value: Double(min(max(percent, 0), 100)), in: 0...100) {
                    Text("Charge")
                } currentValueLabel: {
                    Text(Format.percent(percent))
                }
                .gaugeStyle(.linearCapacity)
                .tint(percent < 30 ? .red : percent < 50 ? .orange : .green)
            }
            if let volts = details?.batteryVoltage {
                LabeledContent("Voltage", value: volts.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " V")
            }
            if details?.batteryPercent == nil, details?.batteryVoltage == nil {
                Text("Unknown").foregroundStyle(.secondary)
            }
        }
    }

    private var coolant: some View {
        Section("Engine") {
            LabeledContent("Coolant temperature",
                           value: details?.coolantTemperatureC.map { Format.temperature(celsius: $0, locale: locale) } ?? String(localized: "Unknown"))
        }
    }

    private var warnings: some View {
        Section("Warning lights") {
            if let warnings = details?.warnings {
                if warnings.isEmpty {
                    Label("No warning lights", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    ForEach(warnings, id: \.self) { key in
                        Label(WarningNames.title(for: key), systemImage: WarningNames.symbol(for: key))
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Text("Unknown").foregroundStyle(.secondary)
            }
        }
    }
}

extension Wheel {
    var title: LocalizedStringKey {
        switch self {
        case .frontLeft: "Front left"
        case .frontRight: "Front right"
        case .rearLeft: "Rear left"
        case .rearRight: "Rear right"
        case .other: "Other"
        }
    }
}
