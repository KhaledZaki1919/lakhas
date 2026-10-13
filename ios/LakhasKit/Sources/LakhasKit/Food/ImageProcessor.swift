import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Photo hygiene (PROJECT_PROMPT.md §3.5): downscale and re-encode as JPEG **without metadata**
/// (no EXIF, no GPS) before anything is sent to a provider or saved on the device.
public enum ImageProcessor {
    public static let uploadMaxPixels = 1568
    public static let thumbnailMaxPixels = 640

    /// Applies the EXIF orientation, scales the long edge to `maxPixels` (never upscales) and
    /// writes a fresh JPEG with only the compression setting, so no source metadata survives.
    public static func prepare(_ imageData: Data, maxPixels: Int = uploadMaxPixels, quality: Double = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encodeJPEG(image, quality: quality)
    }

    public static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Meal photos kept on this device only (ADR-020): protected and excluded from backups.
public struct MealPhotoStore: Sendable {
    public let directory: URL

    public init(location: StoreLocation = AppGroupResolver.resolve()) {
        directory = location.directory.appendingPathComponent("Photos", isDirectory: true)
    }

    init(directory: URL) {
        self.directory = directory
    }

    /// Saves a thumbnail-sized, metadata-free JPEG and returns its file name.
    public func save(_ imageData: Data) throws -> String {
        guard let jpeg = ImageProcessor.prepare(imageData, maxPixels: ImageProcessor.thumbnailMaxPixels, quality: 0.75) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = "\(UUID().uuidString).jpg"
        try FileProtection.write(jpeg, to: directory.appendingPathComponent(name))
        return name
    }

    public func url(for name: String) -> URL { directory.appendingPathComponent(name) }

    public func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}
