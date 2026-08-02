import Foundation

/// What a manifest entry means for this device: the pure comparison between what is published,
/// what is installed, and what this build can read. No I/O — the inputs are facts the caller
/// already holds, which is what makes every branch unit-testable.
public enum CityInstallState: Equatable, Sendable {

    /// Published, compatible, not on disk.
    case notInstalled
    /// On disk at exactly the published version (R37.2: string equality, nothing cleverer).
    case installedCurrent(installedVersion: String)
    /// On disk at some other version, and the published one is readable by this build.
    case updateAvailable(installedVersion: String)
    /// The published file's schema generation is newer than this build reads. Refused, not
    /// deferred — the fossil-install lesson ("user_version N but build knows up to M") pointed
    /// forward: a file from the future must never be downloaded, let alone attached.
    /// `installedVersion` survives so an older compatible copy keeps its affordances.
    case needsNewerApp(installedVersion: String?)

    public init(
        published: CityManifest.City,
        installedVersion: String?,
        newestKnownSchemaVersion: Int = SeedDatabase.newestKnownSchemaVersion
    ) {
        if published.schemaVersion > newestKnownSchemaVersion {
            self = .needsNewerApp(installedVersion: installedVersion)
        } else if let installedVersion {
            self = installedVersion == published.version
                ? .installedCurrent(installedVersion: installedVersion)
                : .updateAvailable(installedVersion: installedVersion)
        } else {
            self = .notInstalled
        }
    }
}
