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

    enum Read {
        case found(FordSession)
        case signedOut
        /// The Keychain refused the read, e.g. before the first unlock after a reboot. Not the same as signed out.
        case unreadable
    }

    static func read() -> Read {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        switch SecItemCopyMatching(q as CFDictionary, &item) {
        case errSecSuccess:
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            guard let data = item as? Data, let session = try? decoder.decode(FordSession.self, from: data) else {
                return .signedOut
            }
            return .found(session)
        case errSecItemNotFound:
            return .signedOut
        default:
            return .unreadable
        }
    }

    static func load() -> FordSession? {
        if case .found(let session) = read() { return session }
        return nil
    }

    /// Delete-then-add so an item written by an older build also picks up the current accessibility class.
    static func save(_ session: FordSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var add = query
        add[kSecValueData as String] = try encoder.encode(session)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw FordError.decoding("Keychain write failed (\(status))") }
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

    private static func read(_ writers: [Writer]) -> [VehicleSnapshot] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return writers
            .compactMap { AppGroup.file($0.fileName) }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(VehicleSnapshot.self, from: $0) }
    }

    /// Newest of both files; the widget's thinner snapshot may win, so the app's detail screens use `load(.app)`.
    static func latest() -> VehicleSnapshot? {
        read([.app, .widget]).max { $0.fetchedAt < $1.fetchedAt }
    }

    static func load(_ writer: Writer) -> VehicleSnapshot? {
        read([writer]).first
    }

    static func clear() {
        for writer in [Writer.app, .widget] {
            if let url = AppGroup.file(writer.fileName) { try? FileManager.default.removeItem(at: url) }
        }
    }
}

/// The garage profile (capabilities, plate, colour). Written by the app only.
enum ProfileStore {
    private static let fileName = "profile.json"

    static func save(_ profile: VehicleProfile) {
        guard let url = AppGroup.file(fileName) else { return }
        try? JSONEncoder().encode(profile).write(to: url, options: .atomic)
    }

    static func load() -> VehicleProfile? {
        guard let url = AppGroup.file(fileName), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VehicleProfile.self, from: data)
    }

    static func clear() {
        if let url = AppGroup.file(fileName) { try? FileManager.default.removeItem(at: url) }
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
        AppGroup.file(fileName).flatMap(load(from:))
    }

    static func load(from url: URL) -> Image? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Image(decorative: image, scale: 1)
    }

    static func clear() {
        if let url = AppGroup.file(fileName) { try? FileManager.default.removeItem(at: url) }
    }
}
