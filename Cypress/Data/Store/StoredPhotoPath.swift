//
//  StoredPhotoPath.swift
//  Cypress — Data/Store
//
//  Turns a photograph path stored in the database into a file that exists today (report F36).
//
//  ── Why a stored absolute path goes stale ─────────────────────────────────────────────────
//  `photos.local_path` and an outbox item's photo path hold absolute paths, such as
//  `/var/mobile/Containers/Data/Application/<UUID>/Library/Application Support/VisitCaptures/x.jpg`.
//  The `<UUID>` part is the app's data container, and iOS can change it when the app updates. iOS
//  moves the files along with the container, so the file is still there; only the prefix the
//  database remembered is wrong. A community add-tree photograph keeps its `local_path` for the
//  life of the installation (it is never uploaded), so after an update its row pointed at a folder
//  that no longer existed, the server had no copy to fall back on, and the viewer said "That
//  photograph could not be opened".
//
//  ── What this does ────────────────────────────────────────────────────────────────────────
//  When the stored path names a file that exists, it is used as it is. When it does not, and the
//  path runs through `Library/Application Support/`, the part after that folder is re-rooted onto
//  the current container's Application Support folder, and used if a file is there. Otherwise the
//  stored path comes back unchanged, so every caller fails exactly as it did before.
//
//  No migration: the rows keep their old strings, and this resolves them on every read. A path
//  segment of `..` is refused, so a stored string cannot climb out of Application Support.
//

import Foundation

enum StoredPhotoPath {

    /// The file a stored photograph path names on this device today.
    ///
    /// - Parameters:
    ///   - stored: the string from `photos.local_path` or an outbox item.
    ///   - applicationSupport: this container's Application Support folder, as it is now.
    static func resolve(
        _ stored: String,
        applicationSupport: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let original = URL(fileURLWithPath: stored)
        if fileManager.fileExists(atPath: original.path) { return original }
        guard let rerooted = rerooted(stored, onto: applicationSupport),
              fileManager.fileExists(atPath: rerooted.path) else { return original }
        return rerooted
    }

    /// The stored path with everything up to `Library/Application Support/` replaced by
    /// `applicationSupport`, or nil when the path does not run through that folder.
    static func rerooted(_ stored: String, onto applicationSupport: URL) -> URL? {
        let components = URL(fileURLWithPath: stored).pathComponents
        // The last match, because the suffix after it is the part the app itself wrote. A home
        // folder's own `Library` (the simulator's `/Users/<name>/Library/Developer/...`) is not
        // followed by `Application Support`, so it is never a match.
        guard components.count > 2,
              let index = (0..<(components.count - 2)).last(where: {
                  components[$0] == "Library" && components[$0 + 1] == "Application Support"
              }) else { return nil }
        let suffix = components[(index + 2)...]
        guard !suffix.isEmpty, !suffix.contains("..") else { return nil }
        return suffix.reduce(applicationSupport) { $0.appendingPathComponent($1) }
    }
}
