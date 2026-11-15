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

struct FordLogoView: View {
    // Image(_:) cannot tell an empty asset slot from a real one, so UIKit is probed; macOS always shows the text.
    private static let hasAsset: Bool = {
        #if canImport(UIKit)
        UIImage(named: "FordLogo") != nil
        #else
        false
        #endif
    }()

    var body: some View {
        if Self.hasAsset {
            Image("FordLogo").resizable().scaledToFit().frame(height: 24)
        } else {
            Text("Ford")
                .font(.custom("SnellRoundhand-Bold", size: 28))
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
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                Text(snapshot.name)
                    .font(.system(size: 26))
                    .foregroundStyle(CardStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 6)
                Image(systemName: "clock").font(.system(size: 14)).foregroundStyle(CardStyle.gray)
                Text(age).font(.system(size: 14)).foregroundStyle(CardStyle.gray).lineLimit(1)
                FordLogoView()
            }
            HStack(alignment: .bottom, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    car.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    lockSymbol
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 6) {
                    row("Fuel level", snapshot.fuelPercent, unit: "%")
                    row("Range", snapshot.rangeKm, unit: "km")
                    row("Mileage", snapshot.odometerKm, unit: "km")
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
            }
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
            Image(systemName: "lock").font(.system(size: 24, weight: .light)).foregroundStyle(CardStyle.gray)
                .accessibilityLabel("Locked")
        case .partlyLocked, .unlocked:
            Image(systemName: "lock.open").font(.system(size: 24, weight: .light)).foregroundStyle(CardStyle.gray)
                .accessibilityLabel("Unlocked")
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder private var car: some View {
        if let carImage {
            carImage.resizable().scaledToFit()
        } else {
            Image(systemName: "car.side.fill").resizable().scaledToFit()
                .foregroundStyle(CardStyle.lightGray).padding(.horizontal, 18).padding(.vertical, 8)
        }
    }

    private func row(_ label: LocalizedStringKey, _ value: Int?, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).font(.system(size: 15)).foregroundStyle(CardStyle.gray).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text(value.map { $0.formatted(.number.locale(locale)) } ?? "–")
                .font(.system(size: 28)).foregroundStyle(CardStyle.ink).lineLimit(1).minimumScaleFactor(0.5)
            Text(unit).font(.system(size: 14)).foregroundStyle(CardStyle.gray)
        }
    }
}
