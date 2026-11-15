import AppKit
import SwiftUI

@main
struct RenderCard {
    @MainActor
    static func main() throws {
        let args = CommandLine.arguments
        let fixture = URL(fileURLWithPath: args[1])
        let output = URL(fileURLWithPath: args[2])
        let now = Date(timeIntervalSince1970: TimeInterval(args[3])!)
        let locale = Locale(identifier: args.count > 4 ? args[4] : "en_DE")

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        let snapshot = VehicleSnapshot.parse(metrics: json["metrics"] as! [String: Any],
                                             vin: "WF0SAMPLE0000000", name: "Focus ST", fetchedAt: now)

        let logo = NSImage(contentsOf: URL(fileURLWithPath: args[5])).map { Image(nsImage: $0) }
        let car = args.count > 6 && args[6] != "-" ? NSImage(contentsOf: URL(fileURLWithPath: args[6])).map { Image(nsImage: $0) } : nil
        let size = args.count > 7 ? args[7].split(separator: "x").compactMap { Double($0) } : [364, 170]
        let card = VehicleCardView(snapshot: snapshot, carImage: car, now: now)
            .environment(\.locale, locale)
            .environment(\.fordLogo, logo)
            .padding(16)
            .frame(width: size[0], height: size[1])
            .background(CardStyle.background)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fatalError("render failed")
        }
        try png.write(to: output)
        print("wrote \(output.path) \(image.width)x\(image.height) fuel=\(snapshot.fuelPercent!) range=\(snapshot.rangeKm!) odometer=\(snapshot.odometerKm!) lock=\(snapshot.lock)")
    }
}
