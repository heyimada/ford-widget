import Foundation
import ImageIO
import Security
import SwiftUI
import UniformTypeIdentifiers

enum AppGroup {
    static let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""

    static func file(_ name: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)?.appendingPathComponent(name)
    }
}

/// The app is the only writer; the widget reads it. AfterFirstUnlock lets the widget read while the phone is locked.
enum SessionStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ford-session",
         kSecAttrAccount as String: "session",
         kSecAttrAccessGroup as String: AppGroup.id]
    }

    static func load() -> FordSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(FordSession.self, from: data)
    }

    static func save(_ session: FordSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(session)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw FordError.decoding("Keychain write failed (\(addStatus))") }
        } else if status != errSecSuccess {
            throw FordError.decoding("Keychain update failed (\(status))")
        }
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// Each process writes only its own file, so the two never race on one path.
enum SnapshotStore {
    enum Writer: String {
        case app, widget
        var fileName: String { "snapshot.\(rawValue).json" }
    }

    static func save(_ snapshot: VehicleSnapshot, as writer: Writer) {
        guard let url = AppGroup.file(writer.fileName) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try? encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    static func latest() -> VehicleSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return [Writer.app, .widget]
            .compactMap { AppGroup.file($0.fileName) }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(VehicleSnapshot.self, from: $0) }
            .max { $0.fetchedAt < $1.fetchedAt }
    }

    static func clear() {
        for writer in [Writer.app, .widget] {
            if let url = AppGroup.file(writer.fileName) { try? FileManager.default.removeItem(at: url) }
        }
    }
}

enum CarImage {
    private static let fileName = "car.png"
    private static let maxWidth: CGFloat = 600

    /// Downscales to at most 600 px wide and stores a PNG; returns false if the bytes are not an image.
    @discardableResult
    static func save(_ data: Data) -> Bool {
        guard let url = AppGroup.file(fileName),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return false }
        let longest = max(width, height) * min(1, maxWidth / width)
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: longest]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    static func load() -> Image? {
        guard let url = AppGroup.file(fileName),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: image, scale: 1)
    }

    static func clear() {
        if let url = AppGroup.file(fileName) { try? FileManager.default.removeItem(at: url) }
    }
}
