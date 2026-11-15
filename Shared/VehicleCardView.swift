import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum CardStyle {
    static let ink = Color(white: 0.1)
    static let gray = Color(white: 0.55)
    static let lightGray = Color(white: 0.82)
    static let fordBlue = Color(red: 0x13 / 255, green: 0x3A / 255, blue: 0x7C / 255)
    static let background = LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom)
}

extension VehicleSnapshot {
    static func sample(now: Date) -> VehicleSnapshot {
        VehicleSnapshot(vin: "WF0SAMPLE0000000", name: "Focus ST", fuelPercent: 57, rangeKm: 267, odometerKm: 44181,
                        lock: .locked, updatedAt: now.addingTimeInterval(-7 * 24 * 3600), fetchedAt: now)
    }
}

private struct FordLogoKey: EnvironmentKey {
    static let defaultValue: Image? = nil
}

extension EnvironmentValues {
    /// Lets a host without an asset catalog (the macOS render script) supply the logo.
    var fordLogo: Image? {
        get { self[FordLogoKey.self] }
        set { self[FordLogoKey.self] = newValue }
    }
}

struct FordLogoView: View {
    @Environment(\.fordLogo) private var injected

    // Image(_:) cannot tell an empty asset slot from a real one, so UIKit is probed; macOS always shows the text.
    private static let hasAsset: Bool = {
        #if canImport(UIKit)
        UIImage(named: "FordLogo") != nil
        #else
        false
        #endif
    }()

    var body: some View {
        if let injected {
            injected.resizable().scaledToFit().frame(height: 15)
        } else if Self.hasAsset {
            Image("FordLogo").resizable().scaledToFit().frame(height: 15)
        } else {
            Text("Ford")
                .font(.custom("SnellRoundhand-Bold", size: 17))
                .foregroundStyle(CardStyle.fordBlue)
        }
    }
}

struct VehicleCardView: View {
    let snapshot: VehicleSnapshot
    let carImage: Image?
    let now: Date
    @Environment(\.locale) private var locale

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                car(width: width * 0.638)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                VStack(alignment: .leading, spacing: 7.7) {
                    header
                    lockSymbol
                }
                rows
                    .frame(width: width * 0.495)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        // The card artwork sits 17.5 pt from the edge, 1.5 pt inside the widget's 16 pt content margins.
        .padding(1.5)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(snapshot.name)
                .font(.system(size: 20))
                .foregroundStyle(CardStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                Image(systemName: "clock")
                Text(age).lineLimit(1)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(CardStyle.gray)
            FordLogoView()
        }
    }

    private var rows: some View {
        VStack(spacing: 5) {
            row("Fuel level", snapshot.fuelPercent, unit: "%")
            row("Range", snapshot.rangeKm, unit: "km")
            row("Mileage", snapshot.odometerKm, unit: "km")
        }
    }

    private var age: String {
        guard let updated = snapshot.updatedAt else { return "–" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = locale
        return formatter.localizedString(for: updated, relativeTo: now)
    }

    @ViewBuilder private var lockSymbol: some View {
        switch snapshot.lock {
        case .locked:
            Image(systemName: "lock").font(.system(size: 21, weight: .light)).foregroundStyle(CardStyle.gray)
                .accessibilityLabel("Locked")
        case .partlyLocked, .unlocked:
            Image(systemName: "lock.open").font(.system(size: 21, weight: .light)).foregroundStyle(CardStyle.gray)
                .accessibilityLabel("Unlocked")
        case .unknown:
            EmptyView()
        }
    }

    // The car image has transparent margins, so it is drawn wider than the card's left half and bleeds into the padding.
    @ViewBuilder private func car(width: CGFloat) -> some View {
        Group {
            if let carImage {
                carImage.resizable().scaledToFit()
            } else {
                Image(systemName: "car.side.fill").resizable().scaledToFit()
                    .foregroundStyle(CardStyle.lightGray).padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
        .frame(width: width)
        .padding(.leading, -13.3)
        .padding(.bottom, -6)
    }

    private func row(_ label: LocalizedStringKey, _ value: Int?, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label).font(.system(size: 12)).foregroundStyle(CardStyle.gray).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text(value.map { $0.formatted(.number.locale(locale)) } ?? "–")
                .font(.system(size: 20).monospacedDigit()).foregroundStyle(CardStyle.ink).lineLimit(1).minimumScaleFactor(0.5)
            Text(unit).font(.system(size: 13)).foregroundStyle(CardStyle.gray)
        }
    }
}
