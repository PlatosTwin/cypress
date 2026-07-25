//
//  VisitAddTreeView.swift
//  Cypress — Features/Visit
//
//  The community add. Reached from screen 02's "None of these? Add this tree" (ERRATA E127).
//
//  **NOT SPECIFIED as a mock.** BUILD-PLAN §9 M2 requires the flow and names its one hard state
//  ("duplicate-proximity warning on add-a-tree"); SCREENS.md draws no screen for it. Per
//  ARCHITECTURE rule 8 nothing is invented where something specified will do, so every part of this
//  is borrowed from the screen that already draws it:
//
//  - the frame, the C1 header and the status chip row are screen 02's, which is where this is
//    entered from and which this is a continuation of;
//  - the photo well is screen 14 §2's dashed well — the same `borderDashedStrong` /
//    `surfaceEmptyThumb` / radius-18 card, tappable for the reason E123 gave: a dashed card is a
//    control when a user action would fill it;
//  - the two photo sources are screen 04's, in the order screen 04 puts them (live session first,
//    photo library as BUILD-PLAN §9 M1's fallback and the only path a simulator can take);
//  - the duplicate warning is C24, which is the component for "this needs something before it can
//    go on", and 02's own `VisitLowAccuracyPanel` is the neighbouring use of it.
//
//  Every decision about *whether* something draws is `VisitAddTreeModel`'s, and every string is
//  `VisitAddTreeCopy`'s, so both halves are testable without a renderer.
//
//  ── The pin ───────────────────────────────────────────────────────────────────────────────
//  This screen used to end with a footnote saying the tree is "recorded where you are standing", and
//  that sentence was the whole of the coordinate story. It is now a statement of the default with the
//  control that changes it underneath (`placementRow`), and the map it opens is `VisitPinAdjustView`.
//  Nothing about the fast path moved: with no pin placed the CTA still writes the fix, and the row
//  above it is one sentence a reader who is standing at the tree scrolls straight past.
//

import PhotosUI
import SwiftUI

struct VisitAddTreeView: View {

    @State private var model: VisitAddTreeModel
    @State private var libraryItem: PhotosPickerItem?

    /// The tree was created — its id, so the caller can open it.
    let onAdded: (UUID) -> Void
    /// The dedupe found a tree already on record here and the reader chose it instead.
    let onOpenExisting: (UUID) -> Void
    let onBack: () -> Void

    init(
        api: any CypressAPI,
        location: VisitLocationProvider,
        attribution: Attribution,
        onAdded: @escaping (UUID) -> Void,
        onOpenExisting: @escaping (UUID) -> Void,
        onBack: @escaping () -> Void
    ) {
        _model = State(
            wrappedValue: VisitAddTreeModel(api: api, location: location, attribution: attribution)
        )
        self.onAdded = onAdded
        self.onOpenExisting = onOpenExisting
        self.onBack = onBack
    }

    var body: some View {
        // The pin screen replaces this one rather than covering it, and that is the same decision as
        // `Phase.placingPin` itself: one model, one draft, one screen in two states. A cover would
        // have put a second `fullScreenCover` inside the one `RootView` already presents this flow
        // through, and the photograph would be sitting behind a modal that owns the whole screen
        // anyway.
        Group {
            if case .placingPin = model.phase {
                pinAdjust
            } else {
                composer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CypressColor.surfaceScreen)
        .task { await model.load() }
        .onDisappear { model.stop() }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    model.useLibraryImage(data)
                }
                libraryItem = nil
            }
        }
    }

    /// The map, anchored on the fix this screen would otherwise have used verbatim.
    @ViewBuilder
    private var pinAdjust: some View {
        if let anchor = model.pinAnchor {
            VisitPinAdjustView(
                anchor: anchor,
                accuracyM: model.fix.accuracyM,
                // Re-opening picks the pin up where it was left, so a second visit is a correction
                // rather than a restart.
                start: model.coordinate,
                onConfirm: { model.confirmPin($0) },
                onCancel: { model.cancelPlacingPin() }
            )
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: VisitAddTreeCopy.title, bottomInset: .wide, onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                    if let gps = model.gpsChipLabel {
                        Chip(gps, style: .meta, leadingDot: CypressColor.gpsDot)
                    }

                    photoWell

                    photoSources

                    placementRow

                    if case let .duplicate(candidates) = model.phase {
                        duplicateWarning(candidates)
                    }

                    if case let .failed(message) = model.phase {
                        Text(message)
                            .cypressBody135(color: CypressColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let reason = model.blockingReason {
                        Text(reason)
                            .cypressBody135(color: CypressColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CypressSpacing.gutter)
                .padding(.bottom, CypressSpacing.gapCandidates)
            }

            footer
        }
    }

    // MARK: - Where the tree goes

    /// One sentence about the coordinate that is about to be written, and the way to change it.
    ///
    /// **It sits between the photograph and the CTA on purpose.** The reader who is standing at the
    /// tree scrolls past it and presses `Add this tree`, and the fast path is still the fast path;
    /// the reader who shot from across the street reads a sentence that is *wrong about them* right
    /// before they commit, which is the only moment at which they would ever think to fix it. Putting
    /// it behind the CTA would have been a second screen nobody visits.
    ///
    /// It draws only with a fix, because `canAdjustPin` is gate 2: there is no map to open without a
    /// centre, and the blocking reason above already explains the missing fix in words.
    @ViewBuilder
    private var placementRow: some View {
        if model.canAdjustPin {
            VStack(alignment: .leading, spacing: CypressSpacing.gapVitality) {
                Text(VisitAddTreeCopy.placement(offsetM: model.pinOffsetM))
                    .cypressBody135(color: CypressColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)

                Button { model.beginPlacingPin() } label: {
                    Text(VisitPinAdjustCopy.openAction)
                        .font(CypressFont.body13Bold)
                        .foregroundStyle(CypressColor.ctaFill)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .cypressHitArea()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - The photo

    /// 14 §2's dashed well, at the height a viewfinder needs rather than a caption's.
    ///
    /// **The card is the base and the contents are an overlay, not a `ZStack`.** A `scaledToFill`
    /// photograph reports a size far larger than the frame it is drawn in, and a `frame(maxWidth:
    /// .infinity)` wrapped around it takes *that* size rather than the proposal — which is what this
    /// screen did on its first run: choosing a photo pushed the whole column wider than the phone and
    /// dragged the header and the CTA off to the left. `.overlay` sizes its content against the base
    /// and lets the excess hang, so the layout is the card's and only the drawing overflows. Seen by
    /// looking, on the simulator, after the tests were green.
    private var photoWell: some View {
        RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous)
            .fill(CypressColor.surfaceEmptyThumb)
            .frame(height: VisitMetrics.AddTree.wellHeight)
            .overlay { wellContents }
            // `.clipShape`, not `.clipped()`: ERRATA E114 is this codebase's own record of an overhang
            // that clipped its drawing and kept its touches, swallowing every control beneath it.
            // Clipping to the shape clips both.
            .clipShape(RoundedRectangle(cornerRadius: CypressRadius.cardLg, style: .continuous))
            .cypressDashedBorder(
                CypressColor.borderDashedStrong,
                radius: CypressRadius.cardLg,
                width: CypressSpacing.Component.outlineWidth
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.hasPhoto ? VisitAddTreeCopy.wellFilled : VisitAddTreeCopy.wellEmpty)
    }

    @ViewBuilder
    private var wellContents: some View {
        if let snapshot = model.snapshot {
            Image(uiImage: snapshot)
                .resizable()
                .scaledToFill()
        } else if model.camera.isLive, let session = model.camera.session {
            VisitCameraPreview(session: session)
        } else {
            // No live session: a simulator, a refusal, or the moment before the session starts.
            // The sentence and nothing else — screen 14's camera glyph is local to that folder by its
            // own note ("no other screen in SCREENS.md uses it"), and borrowing it here would make it
            // a shared component by accident. A dashed frame with one line in it is §5.6's restraint
            // applied to a space that is genuinely still empty.
            Text(VisitAddTreeCopy.wellEmpty)
                .font(CypressFont.body13)
                .foregroundStyle(CypressColor.textFaint)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, CypressSpacing.gutter)
        }
    }

    /// The shutter, the library, and — once there is a frame — the way back to an empty well.
    @ViewBuilder
    private var photoSources: some View {
        if model.hasPhoto {
            SecondaryOutlineButton(VisitAddTreeCopy.retake, style: .compact) { model.retake() }
        } else {
            VStack(spacing: CypressSpacing.gapRows) {
                if model.camera.isLive {
                    PrimaryButton(VisitAddTreeCopy.shutter, style: .compact) {
                        Task { await model.snap() }
                    }
                }
                // Offered whether or not the session is live. BUILD-PLAN §9 M1 names the library as
                // the camera-denied fallback, and it is also the only path a simulator can take —
                // both facts point at the same control, so it is a real one rather than a stub.
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Text(VisitAddTreeCopy.chooseFromLibrary)
                        .font(CypressFont.body13Bold)
                        .foregroundStyle(CypressColor.ctaFill)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .cypressHitArea()
            }
        }
    }

    // MARK: - BUILD-PLAN §9 M2 · the duplicate-proximity warning

    /// What `POST /trees` said, in its own words and with its own candidates.
    ///
    /// C24, not C14: Signal Amber is "this tree needs something" (§1.1), and a refused add with a
    /// list of trees to choose between is precisely a thing needing attention before it goes on the
    /// record. The rows lead to the tree the API found, because the reader's next move — "oh, that
    /// one" — is the whole reason the endpoint returns the list instead of a bare error.
    private func duplicateWarning(_ candidates: [NearbyTree]) -> some View {
        AttentionCard {
            VStack(alignment: .leading, spacing: CypressSpacing.gapRows) {
                AttentionCard<EmptyView>.sectionLabel(VisitAddTreeCopy.duplicateLabel)
                Text(VisitAddTreeCopy.duplicateBody)
                    .cypressBody135(color: CypressColor.textBody)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(candidates) { candidate in
                    Button {
                        onOpenExisting(candidate.tree.id)
                    } label: {
                        HStack(spacing: CypressSpacing.gapCandidates) {
                            Text(VisitAddTreeCopy.candidateName(candidate))
                                .font(CypressFont.listNameSerif)
                                .foregroundStyle(CypressColor.textInk)
                            Spacer(minLength: 0)
                            Text(VisitAddTreeCopy.candidateDistance(candidate))
                                .font(CypressFont.mono12)
                                .foregroundStyle(CypressColor.textMuted)
                                .fixedSize()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .cypressHitArea()
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            PrimaryButton(VisitAddTreeCopy.cta, isEnabled: model.canAdd) {
                Task {
                    if let id = await model.add() { onAdded(id) }
                }
            }
            Text(VisitAddTreeCopy.footnote)
                .cypressBody135(color: CypressColor.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CypressSpacing.gutter)
        .padding(.top, VisitMetrics.Identify.footerTop)
        .padding(.bottom, CypressSpacing.bottomCTA)
    }
}

// MARK: - Copy

/// Every string this screen renders. **None of it is verbatim from a mock** — there is no mock (see
/// the file header) — so each one is here to be argued with in one place, and each states a fact and
/// stops (ARCHITECTURE §5.7).
enum VisitAddTreeCopy {

    /// The C1 title. Screen 02's button says "Add this tree"; the screen it opens is named for the
    /// same act rather than for a different one.
    static let title = "Add this tree"

    static let wellEmpty = "A photo of the tree is required"
    static let wellFilled = "Photo of the tree you are adding"

    static let shutter = "Take the photo"
    static let chooseFromLibrary = "Choose a photo from this phone"
    static let retake = "Use a different photo"

    static let cta = "Add this tree"

    /// Where the coordinate is coming from, in one sentence, above the CTA.
    ///
    /// **The first form used to be the whole story and it was the limitation the owner named.** "The
    /// tree is recorded where you are standing" was true, unavoidable, and wrong about anybody who
    /// photographed a tree from the far kerb. It is now a statement of the *default*, sitting next to
    /// the control that changes it, which is what turns a constraint into a choice.
    ///
    /// The moved form gives the distance and stops. No bearing here, unlike the pin screen's own
    /// sentence: this is a reminder of a decision already taken, and the reader who wants the detail
    /// back presses the control underneath and gets the map with the bearing on it.
    static func placement(offsetM: Double?) -> String {
        guard let offsetM else {
            return "This tree will be recorded where you are standing."
        }
        return "This tree will be recorded \(Int(offsetM.rounded())) m from where you are standing."
    }

    /// What the record will say. Both halves are facts about what `addTree` writes: the source is
    /// `community` and the verification state is `unverified`, which screen 03 prints as
    /// "community-added, unverified".
    ///
    /// It no longer says *where*, because the row above the CTA now owns that and says it more
    /// precisely. One screen must not carry two sentences about the coordinate that can disagree.
    static let footnote =
        "Recorded as community-added and unverified, on this phone."

    static let noPhoto = "A photo is what makes this a record of a tree rather than a pin."
    static let noLocationPending = "Waiting for a fix. A tree is a place, so it cannot be added without one."
    static let noLocationDenied =
        "Cypress cannot see where you are, and a tree is a place. Turn location on in Settings to add one."

    static func photoNotStored(_ error: Error) -> String {
        "That photo could not be saved to this phone: \(error.localizedDescription)"
    }

    static let addFailed = "This tree could not be added. Nothing was recorded."

    /// BUILD-PLAN §9 M2's warning. The number is `TreeDraft.proximityDedupeRadiusM` rather than a
    /// literal, because the sentence is a claim about the rule the API just applied.
    static let duplicateLabel = "ALREADY ON RECORD"
    static var duplicateBody: String {
        "Something is already on record within \(Int(TreeDraft.proximityDedupeRadiusM)) m of here. "
            + "Nothing was added. If one of these is the tree in front of you, open it."
    }

    /// A candidate's name, by the same rule every other surface names a tree: the species common
    /// name, its scientific name, then the honest "we do not know" (`VisitCandidate.displayName`).
    static func candidateName(_ candidate: NearbyTree) -> String {
        candidate.speciesCommonName ?? candidate.speciesScientificName ?? "Unidentified tree"
    }

    /// `4 m` — the API's own measured distance, rounded to the metre. No bearing: `VisitBearing`
    /// needs the origin the distance was measured from, and this list is the API's answer rather
    /// than a ranking this screen performed.
    static func candidateDistance(_ candidate: NearbyTree) -> String {
        "\(Int(candidate.distanceM.rounded())) m"
    }
}
