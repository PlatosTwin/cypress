import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the ingest path needs to know about a staged photo file, and the one thing it has to do to
/// it before storing it.
///
/// **On the import.** ARCHITECTURE §2 draws the layer boundary as a direction — `Data` may not
/// reach up into `DesignSystem` or `Features`, and `Core` stays pure Foundation. `Data` already
/// imports SQLite3 for the same reason it imports ImageIO here: these are the system libraries the
/// storage layer's own job is defined in terms of. No UI framework is imported and nothing here is
/// visible from `Core`.
enum PhotoBinary {

    /// The stored pixel dimensions of an image file, without decoding it.
    ///
    /// Reads the container's metadata only, so it costs a header read rather than a full JPEG
    /// decode — which matters because this runs on the outbox drain for every queued binary.
    ///
    /// `nil` when the file is missing or is not an image the system can read. That is the honest
    /// answer: `Photo.width`/`height` are optional columns, and A3's resolution tie-break is
    /// documented to break ties only between photos whose size is known.
    static func pixelSize(atPath path: String) -> (width: Int, height: Int)? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        return (width: width, height: height)
    }

    /// Copies an image file with its metadata sidecar dropped — GPS, capture time, camera and lens
    /// identity, Maker Notes, IPTC, XMP — leaving the compressed pixels untouched.
    ///
    /// DECISIONS §3.10: "Strip all EXIF server-side on ingest; store capture timestamp and the app's
    /// own fuzzed coordinates in columns." There is no server, so this ingest path is the ingest
    /// path (ERRATA E40). The capture timestamp and the shot type already travel in columns, which
    /// is what makes dropping the sidecar lossless as far as the product is concerned.
    ///
    /// Both passes go through `CGImageDestinationCopyImageSource`, which rewrites the container
    /// around the *original* compressed data: no re-encode, no generation loss, no quality
    /// parameter to get wrong.
    ///
    /// **Why two passes.** ImageIO will not take an exclusion and an orientation in one call —
    /// "kCGImageDestinationExcludeGPS cannot be used with kCGImageDestinationDateTime or
    /// kCGImageDestinationOrientation" — and the exclusion is the only option set that actually
    /// empties the containers. Orientation is not personal data, it is which way up the picture
    /// goes: an iPhone photograph taken in portrait is landscape pixels plus an orientation tag, so
    /// dropping it turns every portrait shot on its side, in the hero and behind the ghost overlay.
    /// So: strip everything, then put that one value back. A file that was already upright skips
    /// the second pass.
    ///
    /// What survives is what ImageIO synthesises for any JPEG it writes — pixel dimensions, colour
    /// space, Exif version — plus the orientation. Nothing in it says where, when, or on what.
    /// `carriesIdentifyingMetadata(atPath:)` is the postcondition, and it names that difference.
    ///
    /// - Throws: `APIError.validationFailed` when the file is not an image container this can
    ///   rewrite. The caller decides what to do about that; it must not decide to publish it.
    static func writeStrippingMetadata(from source: URL, to destination: URL) throws {
        let sourceProperties = CGImageSourceCreateWithURL(source as CFURL, nil)
            .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        let orientation = sourceProperties?[kCGImagePropertyOrientation]
        let needsOrientationRestored = (orientation as? Int).map { $0 != 1 } ?? false

        // `kCFNull` against a container is ImageIO's "remove this one"; an absent key means "carry
        // it across unchanged". The two `ShouldExclude` flags are what ImageIO requires before it
        // will honour any of it, and they take XMP and GPS with them.
        let removed: Any = kCFNull as Any
        let stripping: [CFString: Any] = [
            kCGImagePropertyExifDictionary: removed,
            kCGImagePropertyExifAuxDictionary: removed,
            kCGImagePropertyGPSDictionary: removed,
            kCGImagePropertyIPTCDictionary: removed,
            kCGImagePropertyTIFFDictionary: removed,
            kCGImagePropertyMakerAppleDictionary: removed,
            kCGImageMetadataShouldExcludeXMP: true,
            kCGImageMetadataShouldExcludeGPS: true,
        ]

        let scratch = destination.appendingPathExtension("stripping")
        defer { try? FileManager.default.removeItem(at: scratch) }

        try copyContainer(from: source, to: needsOrientationRestored ? scratch : destination, options: stripping)
        if needsOrientationRestored {
            try copyContainer(
                from: scratch,
                to: destination,
                options: [kCGImageDestinationOrientation: orientation as Any]
            )
        }
    }

    /// The same rewrite, for bytes that have not been a file yet: the capture in memory goes to
    /// `destination` with its sidecar already gone, and the camera's own bytes never exist at a path
    /// anything else can read.
    ///
    /// **Why this exists at all, given `writeStrippingMetadata` above.** That method took a source
    /// *file*, so the only way to use it was to write the capture down first and clean it afterwards
    /// — which is what `LocalAPI.uploadPhoto` does, and it is fine there because the file it cleans
    /// was staged by this app minutes earlier. It is not fine as the general answer, because a path
    /// that stages the raw bytes and then forgets to clean them is indistinguishable from one that
    /// cleans them until somebody reads the file, and that is precisely what happened to the
    /// community add (ERRATA E148). Handing over `Data` removes the step that can be skipped.
    ///
    /// The raw bytes do touch the disk, because ImageIO reads containers from URLs and CFData sources
    /// are not worth the second code path. They touch it in `NSTemporaryDirectory()`, under a name
    /// nothing else knows, and they are removed before this returns — not in the staging directory,
    /// which is backed up and which a killed process would leave a GPS-bearing orphan in.
    ///
    /// - Throws: `APIError.validationFailed` when the bytes are not a container ImageIO can rewrite.
    ///   **Throwing is the point.** Both capture screens already treat a photo that cannot be written
    ///   as no photo — "that photo could not be saved to this phone", the CTA stays disabled — so the
    ///   refusal lands in a designed, retakeable state, at the one moment when the original is still
    ///   in the camera roll and no record has been written. Falling back to the raw bytes here would
    ///   be the leak with a comment on it. (`uploadPhoto` reasons the other way, and says why: by
    ///   then the staged file is the only copy and the row already exists.)
    static func write(_ data: Data, strippingMetadataTo destination: URL) throws {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cypress-strip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let incoming = scratch.appendingPathComponent("incoming")
        let stripped = scratch.appendingPathComponent("stripped")
        try data.write(to: incoming, options: .atomic)
        try writeStrippingMetadata(from: incoming, to: stripped)

        // A rename inside one volume, so the staged file is either absent or complete — the same
        // promise `.atomic` was making, kept the same way. The previous file goes first, because a
        // retake reuses the name.
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: stripped, to: destination)
    }

    /// Cleans a file that is about to become a record, when it may already have been cleaned.
    ///
    /// The backstop for `photos.local_path`, called from the `Data` boundary that writes that column
    /// rather than from the screen that filled it in. The staging path strips at the shutter, so on
    /// the shipping path this reads a header, finds nothing to do, and returns — the cost of the
    /// guarantee is one metadata read per community add.
    ///
    /// It repairs rather than refuses, and that asymmetry with `write(_:strippingMetadataTo:)` is
    /// deliberate: by the time a path reaches here the contributor is pressing "Add this tree" with
    /// a photograph already taken, and a refusal they can only answer by retaking — from a file that
    /// would be refused again — is a flow with no way out of it. Repairing loses nothing: the pixels
    /// are copied, not re-encoded.
    ///
    /// - Throws: `APIError.validationFailed` only when the file both carries identifying metadata and
    ///   cannot be rewritten. Nothing has produced that combination — reading a GPS dictionary out of
    ///   a container means ImageIO knows the container — and if something does, refusing the record is
    ///   the correct end of it.
    static func stripMetadataInPlace(atPath path: String) throws {
        guard carriesIdentifyingMetadata(atPath: path) else { return }
        let file = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: file)
        try write(data, strippingMetadataTo: file)
    }

    /// One container-level rewrite, source to destination, under the given ImageIO options.
    private static func copyContainer(from source: URL, to destination: URL, options: [CFString: Any]) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let type = CGImageSourceGetType(imageSource),
              CGImageSourceGetCount(imageSource) > 0
        else { throw APIError.validationFailed }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL, type, CGImageSourceGetCount(imageSource), nil
        ) else { throw APIError.validationFailed }

        var error: Unmanaged<CFError>?
        let copied = CGImageDestinationCopyImageSource(
            imageDestination, imageSource, options as CFDictionary, &error
        )
        guard copied else {
            error?.release()
            try? FileManager.default.removeItem(at: destination)
            throw APIError.validationFailed
        }
    }

    /// Whether a file still says where it was taken, when, or on what.
    ///
    /// Here rather than in the test target because it is the postcondition of the method above, and
    /// a privacy postcondition only the tests know how to state is one nothing else can check.
    ///
    /// It asks about the fields that identify a person or a place rather than about the presence of
    /// a container, because ImageIO writes an Exif block into every JPEG it produces whether or not
    /// it was given one — dimensions, colour space, a version number. Failing on that would be a
    /// check nothing could ever pass, which is how a privacy check stops being run.
    static func carriesIdentifyingMetadata(atPath path: String) -> Bool {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return false }

        // Whole containers that exist only to identify.
        let containers: [CFString] = [
            kCGImagePropertyGPSDictionary,
            kCGImagePropertyIPTCDictionary,
            kCGImagePropertyMakerAppleDictionary,
            kCGImagePropertyExifAuxDictionary,
        ]
        if containers.contains(where: { properties[$0] != nil }) { return true }

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let exifKeys: [CFString] = [
            kCGImagePropertyExifDateTimeOriginal,
            kCGImagePropertyExifDateTimeDigitized,
            kCGImagePropertyExifLensModel,
            kCGImagePropertyExifLensSerialNumber,
            kCGImagePropertyExifBodySerialNumber,
            kCGImagePropertyExifSubjectLocation,
            kCGImagePropertyExifUserComment,
        ]
        if exifKeys.contains(where: { exif[$0] != nil }) { return true }

        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let tiffKeys: [CFString] = [
            kCGImagePropertyTIFFMake,
            kCGImagePropertyTIFFModel,
            kCGImagePropertyTIFFDateTime,
            kCGImagePropertyTIFFSoftware,
            kCGImagePropertyTIFFArtist,
            kCGImagePropertyTIFFCopyright,
        ]
        return tiffKeys.contains { tiff[$0] != nil }
    }
}
