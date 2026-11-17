import SwiftUI

struct StatusTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: String
    var detail: String?
    var attention = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(attention ? Color.orange : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Two columns always: an odd column count leaves a lone tile on the Duo's wide displays.
struct StatusTiles: View {
    let details: VehicleDetails?
    @Environment(\.locale) private var locale

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            openingTile("Doors", "car.side.front.open", details?.doors)
            openingTile("Windows", "window.vertical.closed", details?.windows)
            hoodTile
            alarmTile
            engineTile
            StatusTile(title: "Outside", symbol: "thermometer.medium",
                       value: details?.outsideTemperatureC.map { Format.temperature(celsius: $0, locale: locale) } ?? unknown)
            StatusTile(title: "Oil life", symbol: "oilcan", value: details?.oilLifePercent.map(Format.percent) ?? unknown,
                       attention: (details?.oilLifePercent ?? 100) < 15)
            StatusTile(title: "12V battery", symbol: "minus.plus.batteryblock",
                       value: details?.batteryPercent.map(Format.percent) ?? unknown,
                       detail: details?.batteryVoltage.map { $0.formatted(.number.precision(.fractionLength(1)).locale(locale)) + " V" })
            tireTile
            warningTile
        }
    }

    private var unknown: String { String(localized: "Unknown") }

    private func openingTile(_ title: LocalizedStringKey, _ symbol: String, _ items: [Opening]?) -> some View {
        let items = items ?? []
        let open = items.filter { $0.state == .open }
        if !open.isEmpty {
            return StatusTile(title: title, symbol: symbol, value: String(localized: "\(open.count) open"),
                              detail: open.map(\.position).joined(separator: ", "), attention: true)
        }
        let allClosed = !items.isEmpty && items.allSatisfy { $0.state == .closed }
        return StatusTile(title: title, symbol: symbol, value: allClosed ? String(localized: "Closed") : unknown)
    }

    private var hoodTile: some View {
        switch details?.hood ?? .unknown {
        case .open: StatusTile(title: "Hood", symbol: "car.side.front.open", value: String(localized: "Open"), attention: true)
        case .closed: StatusTile(title: "Hood", symbol: "car.side.front.open", value: String(localized: "Closed"))
        case .unknown: StatusTile(title: "Hood", symbol: "car.side.front.open", value: unknown)
        }
    }

    private var alarmTile: some View {
        let value: String
        switch details?.alarm ?? .unknown {
        case .armed: value = String(localized: "Armed")
        case .disarmed: value = String(localized: "Disarmed")
        case .triggered: value = String(localized: "Triggered")
        case .unknown: value = unknown
        }
        return StatusTile(title: "Alarm", symbol: "bell.badge", value: value, attention: details?.alarm == .triggered)
    }

    private var engineTile: some View {
        if let ends = details?.remoteStartEndsAt, ends > Date() {
            return StatusTile(title: "Engine", symbol: "engine.combustion", value: String(localized: "Remote start"),
                              detail: String(localized: "Until \(ends.formatted(date: .omitted, time: .shortened))"))
        }
        let value: String
        switch details?.ignition ?? .unknown {
        case .off: value = String(localized: "Off")
        case .on: value = String(localized: "Running")
        case .unknown: value = unknown
        }
        return StatusTile(title: "Engine", symbol: "engine.combustion", value: value)
    }

    private var tireTile: some View {
        let tires = details?.tires ?? []
        let low = tires.filter { $0.status == .low }
        if !low.isEmpty {
            return StatusTile(title: "Tires", symbol: "tirepressure", value: String(localized: "\(low.count) low"), attention: true)
        }
        let allNormal = !tires.isEmpty && tires.allSatisfy { $0.status == .normal }
        return StatusTile(title: "Tires", symbol: "tirepressure", value: allNormal ? String(localized: "Normal") : unknown)
    }

    private var warningTile: some View {
        guard let lit = details?.warnings else {
            return StatusTile(title: "Warnings", symbol: "exclamationmark.triangle", value: unknown)
        }
        let warnings = lit.filter(WarningNames.isWarning)
        if warnings.isEmpty {
            return StatusTile(title: "Warnings", symbol: "checkmark.circle", value: String(localized: "None"))
        }
        return StatusTile(title: "Warnings", symbol: "exclamationmark.triangle", value: "\(warnings.count)",
                          detail: warnings.prefix(2).map(WarningNames.title(for:)).joined(separator: ", "),
                          attention: true)
    }
}
