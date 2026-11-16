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

    /// Whether the file at `path` is a JPEG the system can read.
    ///
    /// The service stores every photograph under `photos/<id>.jpg` and checks nothing about the
    /// bytes, so a file that is not a JPEG would be published under a name that says it is.
    static func isJPEG(atPath path: String) -> Bool {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let type = CGImageSourceGetType(source)
        else { return false }
        return (type as String) == UTType.jpeg.identifier
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
    /// What survives is what ImageIO synthesises for any JPEG it writes — pixel dimensions, color
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
        // will honor any of it, and they take XMP and GPS with them.
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

        try install(stripped, over: destination)
    }

    /// Puts `source` at `destination` in one `rename(2)`, replacing any file already there.
    ///
    /// One call, so at every moment `destination` is either the old file or the new one. The
    /// previous code removed the old file and then moved the new one in: a process killed between the
    /// two left no file at all, and `stripMetadataInPlace` runs over a person's only copy of a
    /// photograph. Both paths are in one folder or under one temporary root on the same volume, which
    /// `rename` requires; across volumes it fails and leaves `destination` as it was.
    ///
    /// - Parameter rename: the swap itself. Only a test passes one, to fail it.
    static func install(
        _ source: URL,
        over destination: URL,
        rename: (URL, URL) throws -> Void = PhotoBinary.rename
    ) throws {
        try rename(source, destination)
    }

    /// `rename(2)`, which replaces `to` atomically when both are on one volume.
    static func rename(_ from: URL, _ to: URL) throws {
        guard Foundation.rename(from.path, to.path) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: to.path])
        }
    }

    /// Whether ImageIO can read the file at `path` as an image.
    static func isReadableImage(atPath path: String) -> Bool {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              CGImageSourceGetType(source) != nil
        else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// A JPEG of the image at `source`, written to `destination`, with nothing in it but the pixels
    /// and which way up they go.
    ///
    /// For a file that is not a JPEG: a HEIC or PNG from the photo library, which the ingest path
    /// keeps in its own container (`copyContainer` writes the source's type). The service names every
    /// photograph `photos/<id>.jpg`, so such a file is sent as this copy. This re-encodes, unlike the
    /// strip above, and is used only where the original cannot be sent as it is. The person's own
    /// file is not touched.
    ///
    /// The image is decoded and encoded fresh, so no metadata container of the source is carried
    /// across. The orientation tag is written back, for the reason `writeStrippingMetadata` gives.
    ///
    /// - Throws: `APIError.validationFailed` when the file is not an image ImageIO can decode.
    static func writeJPEGCopy(from source: URL, to destination: URL) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0,
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { throw APIError.validationFailed }
        let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation = properties?[kCGImagePropertyOrientation] as? Int, orientation != 1 {
            options[kCGImagePropertyOrientation] = orientation
        }
        guard let imageDestination = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw APIError.validationFailed }
        CGImageDestinationAddImage(imageDestination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(imageDestination) else {
            try? FileManager.default.removeItem(at: destination)
            throw APIError.validationFailed
        }
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
    static func stripMetadataInPlace(
        atPath path: String,
        rename: (URL, URL) throws -> Void = PhotoBinary.rename
    ) throws {
        guard carriesIdentifyingMetadata(atPath: path) else { return }
        let file = URL(fileURLWithPath: path)
        // The clean copy is made next to the file, so the swap is a rename inside one folder: the
        // temporary directory `write` uses may be on another volume, where `rename` cannot replace.
        let clean = file.deletingLastPathComponent()
            .appendingPathComponent(".\(file.lastPathComponent)-\(UUID().uuidString)\(cleanCopySuffix)")
        // Registered before the file exists and released after it is gone, so a sweep that runs while
        // this strip is in progress leaves its copy alone (`removeAbandonedCleanCopies`).
        stripsInProgress.insert(clean.lastPathComponent)
        defer {
            try? FileManager.default.removeItem(at: clean)
            stripsInProgress.remove(clean.lastPathComponent)
        }
        try writeStrippingMetadata(from: file, to: clean)
        try install(clean, over: file, rename: rename)
    }

    /// The end of the name `stripMetadataInPlace` gives its clean copy.
    private static let cleanCopySuffix = ".clean"

    /// The end of the name `writeStrippingMetadata` gives its own scratch file, beside its
    /// destination. When the destination is a clean copy, that scratch is part of the same strip.
    private static let strippingScratchSuffix = ".stripping"

    /// The clean copies of strips running in this process now, by file name.
    private static let stripsInProgress = InProgressNames()

    /// Removes the clean copies that strips killed part-way left in `directory`, and returns the
    /// files it removed.
    ///
    /// `stripMetadataInPlace` removes its copy in a `defer`, which does not run when the process is
    /// killed during the strip. Nothing reads such a file; it only takes disk space.
    ///
    /// A file is removed only when its name has the exact shape that method gives its copy,
    /// `.<name>-<UUID>.clean`, or that copy's own scratch, `.<name>-<UUID>.clean.stripping`, and only
    /// when no strip in this process holds that name. A strip holds its name from before the file
    /// is created until after it is removed or renamed, and every name carries a fresh UUID, so a
    /// copy that is in progress is never removed, whenever this runs. The app is one process, so a
    /// copy no strip in this process holds is one a killed process left. Folders, and names that
    /// only look similar, are kept.
    @discardableResult
    static func removeAbandonedCleanCopies(in directory: URL) -> [URL] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { return [] }
        var removed: [URL] = []
        for name in names {
            guard let copyName = cleanCopyName(of: name) else { continue }
            let file = directory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue
            else { continue }
            // Checked and removed under the lock, so a strip cannot take this name in between. It
            // never would: the name carries a UUID that only the strip that made it ever used.
            let didRemove = stripsInProgress.unlessHeld(copyName) {
                (try? manager.removeItem(at: file)) != nil
            }
            if didRemove == true { removed.append(file) }
        }
        return removed
    }

    /// The clean copy's file name when `name` is a clean copy or its scratch, and nil otherwise.
    static func cleanCopyName(of name: String) -> String? {
        let copyName = name.hasSuffix(cleanCopySuffix + strippingScratchSuffix)
            ? String(name.dropLast(strippingScratchSuffix.count))
            : name
        guard copyName.hasPrefix("."), copyName.hasSuffix(cleanCopySuffix) else { return nil }
        // `.<name>-<UUID>.clean`: a UUID is 36 characters, after a hyphen, after at least one
        // character of the photo's own name.
        let body = copyName.dropFirst().dropLast(cleanCopySuffix.count)
        let uuidLength = 36
        guard body.count >= uuidLength + 2 else { return nil }
        let uuid = body.suffix(uuidLength)
        let hyphen = body.dropLast(uuidLength).last
        guard hyphen == "-", UUID(uuidString: String(uuid)) != nil else { return nil }
        return copyName
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
    /// it was given one — dimensions, color space, a version number. Failing on that would be a
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

/// A set of file names behind a lock: the clean copies `PhotoBinary` is writing now.
final class InProgressNames: @unchecked Sendable {
    private let lock = NSLock()
    private var names: Set<String> = []

    func insert(_ name: String) {
        lock.lock()
        names.insert(name)
        lock.unlock()
    }

    func remove(_ name: String) {
        lock.lock()
        names.remove(name)
        lock.unlock()
    }

    /// Runs `body` while holding the lock, and returns its result, unless `name` is held. Returns
    /// nil when it is held.
    func unlessHeld<T>(_ name: String, _ body: () -> T) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard !names.contains(name) else { return nil }
        return body()
    }
}
