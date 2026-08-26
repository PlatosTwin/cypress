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
    /// Reachable four ways, all of them "you already have this": the record dates match (the steady
    /// state), the published one is *older* (a publish was skipped after a bundle build), the bundle
    /// holds a city the catalog does not list at all, or **the bundle holds it and no record date
    /// derives** — `contentRev` is nil in that last one.
    ///
    /// **The optionality is load-bearing and was paid for.** `contentRev` was briefly non-optional,
    /// which forced the caller's `nil` to carry two meanings — "the bundle does not hold this city"
    /// and "the bundle holds it, dateless" — and the second fell through to `.notInstalled`, whose
    /// `allowsDownload` is true. That is `81 MB` and a `Download` button for a city on the reader's
    /// phone: the exact defect this type was changed to remove, reintroduced by a shape that could
    /// not tell presence from freshness. Reachable, not theoretical — `Tools/build_seed.py` writes
    /// San Jose's snapshot date with an empty-string default and no `die()` behind it, where the
    /// San Francisco path has one (`SeedCities.contentRev`'s note has the detail).
    /// **Being in the bundle is the fact; having a date is a separate, weaker fact.**
    case bundled(contentRev: String?)
    /// Inside the app bundle, and the published file carries a strictly later record date. The
    /// `Update` button is honest here because it now buys something.
    ///
    /// **What the downloaded copy then does is shadowing, not switching**: it replaces
    /// the bundled rows of that city's whole id space inside the union, and every *other* bundled
    /// city stays on the map. The `active-city` marker this comment used to name is gone, with the
    /// exclusive switch it belonged to.
    case bundledOutdated(bundledContentRev: String)

    /// **Inside the app bundle, and a downloaded copy has replaced the bundled rows for it.**
    ///
    /// **A downloaded newer copy of a bundled city is an update to that city's data, not a second
    /// inventory beside it.** That is the state this case exists for, and the one the enum had no
    /// case for at all — which is exactly why
    /// `CityInstallState.init` could never reach `.bundled` again for a city that had been
    /// downloaded once, and why San Francisco drew `Installed · <version>` with `Use` and `Remove`
    /// beside a built-in card simultaneously claiming to include it.
    ///
    /// - Parameter installedContentRev: the record date of the copy that is actually drawing, read
    ///   out of its own `seed_meta`. Optional on the same terms as `.bundled`'s: being on the phone
    ///   is the fact, and having a date is a separate, weaker one.
    /// - Parameter updateAvailable: whether the catalog has moved ahead of *that copy* too. A
    ///   downloaded update can itself go stale and the row has to be able to say so. It is this
    ///   state's second half rather than a fourth state, because what the reader is looking at is
    ///   one city with one record and at most one offer.
    case bundledUpdated(installedContentRev: String?, updateAvailable: Bool)

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
        case let .bundledUpdated(_, updateAvailable):
            // A downloaded copy that is itself behind the catalog. The fetch buys a newer record
            // for a city already on the phone, which is the same trade `.bundledOutdated` offers
            // one step earlier.
            return updateAvailable
        case .installedCurrent, .needsNewerApp, .bundled:
            return false
        }
    }

    /// Whether the device already holds a copy of this city — downloaded, or inside the app bundle.
    ///
    /// **Stated here, beside `allowsDownload`, because it is the same kind of fact**: a property of
    /// the state rather than of the row that draws it, so the Cities screen's sectioning and its
    /// buttons cannot come to different conclusions about what is on the phone. The two are not
    /// opposites — `.updateAvailable` and `.bundledOutdated` are both on the device *and* worth
    /// fetching, which is exactly the pair a reader needs told apart.
    public var isOnDevice: Bool {
        switch self {
        case .installedCurrent, .updateAvailable, .bundled, .bundledOutdated, .bundledUpdated:
            return true
        case .notInstalled:
            return false
        case let .needsNewerApp(installedVersion):
            // The published file is refused; an older compatible copy is still on the phone, and
            // that copy is the whole reason this case carries a version at all.
            return installedVersion != nil
        }
    }

    /// Whether the **app's own bundle** holds this city, in any of the three states it can be in.
    ///
    /// Decides where the Cities screen files the card: a bundled city is nested under the built-in
    /// inventory rather than drawn beside it, because it is not something
    /// the reader can add or remove. Stated here beside `isOnDevice` and `allowsDownload` for the
    /// same reason those two are — one type knows what the device holds, and the screen's
    /// sectioning, its buttons and its copy must not reach different conclusions about it.
    public var isBundledCity: Bool {
        switch self {
        case .bundled, .bundledOutdated, .bundledUpdated:
            return true
        case .notInstalled, .installedCurrent, .updateAvailable, .needsNewerApp:
            return false
        }
    }

    /// - Parameter bundled: the city as the app's own bundle holds it (`SeedCities`), or nil when
    ///   the bundle does not hold it.
    ///
    ///   **A whole `City`, not its date.** Passing `String?` here is what let presence and freshness
    ///   collapse into one `nil`; a caller cannot hand this parameter a record date without also
    ///   handing it a city, so the collapse is no longer expressible. See `.bundled`.
    /// - Parameters:
    ///   - installedContentRev: the record date the installed copy actually holds, read out of its
    ///     own `seed_meta` (`CityLibrary.InstalledCity.contentRev`).
    ///   - installedSchemaVersion: the generation stamped into that same copy.
    ///
    ///   **Why a version-string comparison was not enough, and what these two are for.** R37.2 said
    ///   update detection is string equality on `version`, and R60 then appended a `build_id` to
    ///   that string — *the first 8 hex of the source seed's sha256*, a fact about the 108 MB fused
    ///   seed a pack was cut from and not about the pack. So re-running the publisher over a
    ///   rebuilt seed changes `version` for **every** city while changing no city's data, and every
    ///   device holding any of them is told an update is available for bytes it already has.
    ///
    ///   Measured, not theorized: a tester downloaded Manhattan at
    ///   `s17-r2026-08-22-4f6ebaaa` and was offered an update to `s17-r2026-08-22-ac7b1ccc`
    ///   minutes later — same generation, same record date, different source seed — and filed it as
    ///   a bug (build 49, 2026-08-23). It is one.
    ///
    ///   The comparison therefore asks what an update would actually buy: a newer **record**, or a
    ///   newer **generation**. Both are read from keys the publisher writes for the purpose —
    ///   `content_rev` and `schema_version` in the manifest, `publish_content_rev` and
    ///   `publish_schema_version` in the file — so **nothing here parses a version string**, which
    ///   is the property `CityManifest.City.version`'s own comment asks callers to preserve.
    ///
    ///   **Missing facts fall back to string equality**, which is the safe direction: an update
    ///   offered needlessly costs bytes, an update withheld wrongly costs a stale inventory with
    ///   nothing on screen to explain it. A copy installed before this was recorded, or a file whose
    ///   receipt does not answer, therefore behaves exactly as it did before.
    public init(
        published: CityManifest.City,
        installedVersion: String?,
        installedContentRev: String? = nil,
        installedSchemaVersion: Int? = nil,
        bundled: SeedCities.City? = nil,
        newestKnownSchemaVersion: Int = SeedDatabase.newestKnownSchemaVersion
    ) {
        // ── The bundle is asked FIRST, and that ordering is the defect this round exists to fix ──
        //
        // This used to read `else if let installedVersion` *before* `else if let bundled`, so the
        // moment a downloaded copy of San Francisco existed the `bundled` argument was never
        // consulted at all: the row resolved to `.installedCurrent` or `.updateAvailable`, and
        // `CityDownloadRow.decide` drew `Installed · <version>` with `Use` and `Remove` — beside a
        // built-in card simultaneously saying `Includes San Francisco and San Jose`. The `.bundled`
        // and `.bundledOutdated` cases, which exist precisely to stop a bundled city being offered
        // as a download, were unreachable for any city that had ever been downloaded once.
        //
        // Reordering alone would have been the wrong fix and would have hidden the downloaded copy
        // instead: a bundled city *with* a downloaded copy is a real state — the one where the
        // downloaded copy is an update to that city's data rather than a peer inventory — and it
        // needed a case of its own (`.bundledUpdated`). Both halves are here, and
        // `BundledCityTests` pins the pair.
        if published.schemaVersion > newestKnownSchemaVersion {
            // The schema gate still refuses the download. What changes is what the row *says* when
            // there is nothing to refuse: a bundled city with no downloaded copy is already on the
            // reader's phone, and "Needs a newer app" for a city they are looking at is the same
            // class of falsehood this round exists to remove. Both branches draw no button.
            //
            // **Ruled by the owner, 2026-08-14**, on review finding 8: when the published entry is
            // BOTH a newer schema generation and a newer record, this row keeps `Included in the
            // app` and states neither the format refusal nor the newer record. Revisiting what such
            // a row owes the reader belongs to the round that bumps the published format, not here.
            if let bundled {
                // A city the bundle holds is on the phone whether or not a newer copy was ever
                // downloaded, and neither branch may offer a file this build cannot read.
                self = installedVersion == nil
                    ? .bundled(contentRev: bundled.contentRev)
                    : .bundledUpdated(
                        installedContentRev: installedContentRev, updateAvailable: false
                    )
            } else {
                self = .needsNewerApp(installedVersion: installedVersion)
            }
        } else if let bundled {
            // **`content_rev`, never the version string.** The manifest carries `content_rev` as
            // its own key (it always has; `CityManifest.City` simply did not decode it), so this
            // comparison never splits `version` on `-` — the property `CityManifest.City.version`'s
            // own comment asks callers to preserve. R60's `build_id` segment is why the bundle
            // could not reconstruct a version string anyway: it is a hash of 108 MB.
            //
            // Both revisions are the ISO dates `content_rev_for` produces, where lexicographic
            // order is date order. Anything that does not compare strictly later — an equal date,
            // an earlier one, an absent published rev, **or a bundled city with no date at all** —
            // lands on `.bundled`, which offers nothing. That is the safe direction in every one of
            // those cases: the cost of withholding a download is a stale record, and the cost of
            // offering one is 81 MB of bytes the reader already has.
            if let installedVersion {
                // **A downloaded copy of a bundled city is an update to that city, not a peer
                // inventory**. It shadows the bundled rows of that id space inside the
                // union and nothing else moves, so the row states the record the reader is actually
                // looking at and offers to undo it — never `Remove`, which would read as removing a
                // city the app cannot remove.
                //
                // Whether *that copy* is itself behind the catalog is the same question
                // `.updateAvailable` asks, asked with the same helper, so a bundled city and a
                // non-bundled pack cannot come to different conclusions about identical facts.
                self = .bundledUpdated(
                    installedContentRev: installedContentRev,
                    updateAvailable: !Self.installedIsCurrent(
                        published: published,
                        installedVersion: installedVersion,
                        installedContentRev: installedContentRev,
                        installedSchemaVersion: installedSchemaVersion
                    )
                )
            } else if let publishedRev = published.contentRev,
                      let bundledRev = bundled.contentRev,
                      publishedRev > bundledRev {
                self = .bundledOutdated(bundledContentRev: bundledRev)
            } else {
                self = .bundled(contentRev: bundled.contentRev)
            }
        } else if let installedVersion {
            // A pack the bundle does not cover. Its own record is the only one there is.
            self = Self.installedIsCurrent(
                published: published,
                installedVersion: installedVersion,
                installedContentRev: installedContentRev,
                installedSchemaVersion: installedSchemaVersion
            )
                ? .installedCurrent(installedVersion: installedVersion)
                : .updateAvailable(installedVersion: installedVersion)
        } else {
            self = .notInstalled
        }
    }

    /// Whether the installed copy already holds what the published entry offers.
    ///
    /// Two ways to be current, in order of what they cost to establish:
    ///
    /// 1. **The version strings match.** R37.2's original rule, unchanged and still first — when it
    ///    says yes there is nothing more to ask.
    /// 2. **The record date and the generation both match.** The strings differ, so *something*
    ///    about the publish differed; this decides whether that something was the data. Both halves
    ///    are required and both must be *known* — a nil on either side is not a match, because "the
    ///    file did not say" and "the file said the same thing" are different answers and only one of
    ///    them justifies withholding an update.
    ///
    /// The published record date is `content_rev`, its own manifest key since #156; the installed
    /// one is `publish_content_rev`, written into every published file by `publish_cities.py`. No
    /// substring of `version` is examined on either side.
    private static func installedIsCurrent(
        published: CityManifest.City,
        installedVersion: String,
        installedContentRev: String?,
        installedSchemaVersion: Int?
    ) -> Bool {
        if installedVersion == published.version { return true }
        guard let installedContentRev, let publishedContentRev = published.contentRev,
              let installedSchemaVersion
        else { return false }
        return installedContentRev == publishedContentRev
            && installedSchemaVersion == published.schemaVersion
    }
}
