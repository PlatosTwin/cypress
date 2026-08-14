import Foundation

/// What a manifest entry means for this device: the pure comparison between what is published,
/// what is installed, **what the app bundle already holds**, and what this build can read. No I/O —
/// the inputs are facts the caller already holds, which is what makes every branch unit-testable.
public enum CityInstallState: Equatable, Sendable {

    /// Published, compatible, not on disk and not in the bundle.
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
    /// **Inside the app bundle**, at a record date the published file does not beat. There is
    /// nothing to download and no button is drawn — R43 §3's own principle, stated there for the
    /// schema-too-new case: a button that cannot keep its promise is not drawn.
    ///
    /// Reachable three ways, all of them "you already have this": the record dates match (the
    /// steady state), the published one is *older* (a publish was skipped after a bundle build), or
    /// the bundle holds a city the catalog does not list at all.
    case bundled(contentRev: String)
    /// Inside the app bundle, and the published file carries a strictly later record date. The
    /// `Download` button is honest here because it now buys something; the downloaded copy shadows
    /// the bundled one through the existing `active-city` marker, with no new mechanism.
    case bundledOutdated(bundledContentRev: String)

    /// Whether a download of the published file is permitted **at all**.
    ///
    /// **This is the only statement of that rule.** `CityDownloadRow.decide` draws the affordance
    /// from it and `CityDownloadsModel.download` refuses on it, so "the button is drawn" and "the
    /// download runs" cannot drift apart — which is what makes a second copy of a city the device
    /// already holds structurally impossible rather than merely unreachable. A view that somehow
    /// sends a stale action gets nothing.
    public var allowsDownload: Bool {
        switch self {
        case .notInstalled, .updateAvailable, .bundledOutdated:
            return true
        case .installedCurrent, .needsNewerApp, .bundled:
            return false
        }
    }

    /// - Parameter bundledContentRev: the record date the app's own bundle holds this city at
    ///   (`SeedCities`), or nil when the bundle does not hold it.
    public init(
        published: CityManifest.City,
        installedVersion: String?,
        bundledContentRev: String? = nil,
        newestKnownSchemaVersion: Int = SeedDatabase.newestKnownSchemaVersion
    ) {
        if published.schemaVersion > newestKnownSchemaVersion {
            // The schema gate still refuses the download. What changes is what the row *says* when
            // there is nothing to refuse: a bundled city with no downloaded copy is already on the
            // reader's phone, and "Needs a newer app" for a city they are looking at is the same
            // class of falsehood this round exists to remove. Both branches draw no button.
            if installedVersion == nil, let bundledContentRev {
                self = .bundled(contentRev: bundledContentRev)
            } else {
                self = .needsNewerApp(installedVersion: installedVersion)
            }
        } else if let installedVersion {
            // A downloaded copy shadows the bundle (the `active-city` marker points at it), so its
            // version — a full R37 string, not just a date — is the fact worth stating.
            self = installedVersion == published.version
                ? .installedCurrent(installedVersion: installedVersion)
                : .updateAvailable(installedVersion: installedVersion)
        } else if let bundledContentRev {
            // **`content_rev`, never the version string.** The manifest carries `content_rev` as
            // its own key (it always has; `CityManifest.City` simply did not decode it), so this
            // comparison never splits `version` on `-` — the property `CityManifest.City.version`'s
            // own comment asks callers to preserve. R60's `build_id` segment is why the bundle
            // could not reconstruct a version string anyway: it is a hash of 108 MB.
            //
            // Both revisions are the ISO dates `content_rev_for` produces, where lexicographic
            // order is date order. A rev that is not such a date compares unequal and lands on
            // `.bundled`, which offers nothing — the safe direction, since the failure of an
            // unrecognized rev is a download withheld rather than 81 MB of bytes already held.
            if let publishedRev = published.contentRev, publishedRev > bundledContentRev {
                self = .bundledOutdated(bundledContentRev: bundledContentRev)
            } else {
                self = .bundled(contentRev: bundledContentRev)
            }
        } else {
            self = .notInstalled
        }
    }
}
