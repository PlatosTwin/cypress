//
//  VisitCameraView.swift
//  Cypress — Features/Visit
//
//  Screen 04 · Visit (dark camera)
//  "The camera opens straight to a ghost overlay of the last photo so the timeline stays
//  comparable. Note and phenology tag are optional; offline, submit still succeeds. Phenology chips
//  come from the species record, so an evergreen never gets asked about fall color."
//
//  Dark **always**, regardless of the system setting (ARCHITECTURE §6) — `.cypressForcedDark()`.
//

import PhotosUI
import SwiftUI

struct VisitCameraView: View {

    @State private var model: VisitCameraModel
    @State private var libraryItem: PhotosPickerItem?

    let onSaved: (VisitSaveReceipt) -> Void
    let onClose: () -> Void

    init(
        treeID: UUID,
        treeDisplayName: String,
        gpsAccuracyM: Double?,
        api: any CypressAPI,
        outbox: OutboxQueue,
        attribution: Attribution,
        onSaved: @escaping (VisitSaveReceipt) -> Void,
        onClose: @escaping () -> Void
    ) {
        _model = State(wrappedValue: VisitCameraModel(
            treeID: treeID,
            treeDisplayName: treeDisplayName,
            gpsAccuracyM: gpsAccuracyM,
            api: api,
            outbox: outbox,
            attribution: attribution
        ))
        self.onSaved = onSaved
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            viewfinder
            tray
        }
        .background(CypressColor.Dark.bgCamera)
        .ignoresSafeArea(edges: .top)
        .cypressForcedDark()
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

    // MARK: - Viewfinder

    private var viewfinder: some View {
        ZStack {
            base

            // ══════════════════════════════════════════════════════════════════════════════════
            // THE GHOST OVERLAY — the last full-tree photo at 30 % opacity.
            //
            // This is the single artefact the docs say the official city app will never have. It
            // is drawn *over* the live preview and *under* the framing furniture, and it goes away
            // the moment a frame is taken, because at that point there is nothing left to line up.
            // ══════════════════════════════════════════════════════════════════════════════════
            if !model.hasSnapped {
                ghostLayer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay(alignment: .topLeading) { closeButton }
        .overlay(alignment: .top) { guidancePill }
        .overlay { framingCorners }
        .overlay(alignment: .bottom) { shotTypeChips }
        .overlay(alignment: .bottom) { shutter }
        .overlay(alignment: .bottomLeading) { ghostCaption }
    }

    @ViewBuilder
    private var base: some View {
        if let snapshot = model.snapshot {
            Image(uiImage: snapshot)
                .resizable()
                .scaledToFill()
                .accessibilityLabel("The photo you just took")
        } else if model.camera.isLive, let session = model.camera.session {
            VisitCameraPreview(session: session)
        } else {
            // No session: a simulator, a refusal, or the moment before the session starts. The
            // documented viewfinder gradient, so the screen still reads as a viewfinder.
            VisitViewfinderPlaceholder()
        }
    }

    @ViewBuilder
    private var ghostLayer: some View {
        if let ghost = model.ghost {
            Image(uiImage: ghost)
                .resizable()
                .scaledToFill()
                .opacity(VisitMetrics.Camera.ghostOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if !model.camera.isLive {
            // First visit, no camera: `CypressGradient.cameraGhost` is the spec's stand-in for the
            // alignment layer, so the screen's own subject is visible in a simulator. It is never
            // drawn over a live preview — an invented ghost on a real camera would be a lie about
            // where the last photo was taken from.
            CypressGradientField(CypressGradient.cameraGhost)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var guidancePill: some View {
        Text(model.guidance)
            .font(CypressFont.body13)
            .foregroundStyle(VisitColor.guidancePillText)
            .padding(.vertical, VisitMetrics.Camera.guidancePillPaddingV)
            .padding(.horizontal, VisitMetrics.Camera.guidancePillPaddingH)
            .background {
                Capsule()
                    .fill(VisitColor.guidancePillFill)
                    .background { Capsule().fill(.ultraThinMaterial) }
            }
            .padding(.top, VisitMetrics.Camera.guidancePillTop)
            .allowsHitTesting(false)
    }

    private var framingCorners: some View {
        ZStack {
            ForEach(VisitFramingCorner.Corner.allCases, id: \.self) { corner in
                VisitFramingCorner(corner: corner)
                    .stroke(
                        CypressColor.cameraFramingCorner,
                        lineWidth: VisitMetrics.Camera.framingCornerStroke
                    )
                    .frame(
                        width: VisitMetrics.Camera.framingCornerSide,
                        height: VisitMetrics.Camera.framingCornerSide
                    )
                    .padding(.top, VisitMetrics.Camera.framingCornerTop)
                    .padding(.bottom, VisitMetrics.Camera.framingCornerBottom)
                    .padding(.horizontal, VisitMetrics.Camera.framingCornerInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var shotTypeChips: some View {
        HStack(spacing: VisitMetrics.Camera.shotTypeGap) {
            ForEach(model.shotTypes, id: \.self) { type in
                Chip(
                    model.label(for: type),
                    style: model.shotType == type ? .shotTypeOn : .shotTypeOff,
                    action: { model.shotType = type }
                )
            }
        }
        .padding(.bottom, VisitMetrics.Camera.shotTypeBottom)
    }

    @ViewBuilder
    private var shutter: some View {
        VStack(spacing: CypressSpacing.gapRows) {
            if model.camera.needsLibraryFallback {
                // Same treatment as the guidance pill: this sentence sits on the viewfinder, and
                // plain text there is unreadable against a photograph.
                Text(fallbackReason)
                    .font(CypressFont.body125)
                    .foregroundStyle(VisitColor.guidancePillText)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, VisitMetrics.Camera.guidancePillPaddingV)
                    .padding(.horizontal, VisitMetrics.Camera.guidancePillPaddingH)
                    .background {
                        Capsule()
                            .fill(VisitColor.guidancePillFill)
                            .background { Capsule().fill(.ultraThinMaterial) }
                    }
                    .padding(.horizontal, CypressSpacing.gutter)
            }

            if model.camera.needsLibraryFallback {
                PhotosPicker(selection: $libraryItem, matching: .images, photoLibrary: .shared()) {
                    VisitShutterButton(isLibrary: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose a photo from your library")
            } else {
                Button {
                    if model.hasSnapped {
                        model.retake()
                    } else {
                        Task { await model.snap() }
                    }
                } label: {
                    VisitShutterButton(isLibrary: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.hasSnapped ? "Take another photo" : "Take the photo")
            }
        }
        .padding(.bottom, VisitMetrics.Camera.shutterBottom)
    }

    private var fallbackReason: String {
        switch model.camera.availability {
        case .denied:
            // BUILD-PLAN §9: "camera permission ask and denied fallback (photo library)".
            return "Camera access is off. Add the photo from your library instead."
        case .unavailable, .failed:
            return "No camera available here. Add the photo from your library instead."
        default:
            return ""
        }
    }

    @ViewBuilder
    private var ghostCaption: some View {
        if !model.hasSnapped {
            Text(model.ghost == nil ? "no ghost yet · first photo" : "ghost overlay 30%")
                .font(CypressFont.mono105)
                .foregroundStyle(VisitColor.ghostCaption)
                .lineSpacing(VisitMetrics.Camera.ghostCaptionLineSpacing)
                .frame(maxWidth: VisitMetrics.Camera.ghostCaptionMaxWidth, alignment: .leading)
                .padding(.leading, VisitMetrics.Camera.ghostCaptionLeading)
                .padding(.bottom, VisitMetrics.Camera.ghostCaptionBottom)
                .allowsHitTesting(false)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            ZStack {
                Circle().fill(VisitColor.cameraCloseFill)
                VisitCloseGlyph()
                    .stroke(
                        CypressColor.Dark.textSecondary,
                        style: StrokeStyle(
                            lineWidth: VisitMetrics.Camera.closeStroke,
                            lineCap: .round
                        )
                    )
                    .frame(width: VisitMetrics.Camera.closeGlyph, height: VisitMetrics.Camera.closeGlyph)
            }
            .frame(width: VisitMetrics.Camera.closeButton, height: VisitMetrics.Camera.closeButton)
        }
        .buttonStyle(.plain)
        .padding(.top, CypressSpacing.Device.statusBarInset)
        .padding(.leading, CypressSpacing.gutter)
        .accessibilityLabel("Close the camera")
    }

    // MARK: - Tray

    private var tray: some View {
        VStack(spacing: VisitMetrics.Camera.traySpacing) {
            noteField

            if !model.availablePhenologyTags.isEmpty {
                phenologyChips
            }

            logVisitButton

            offlineLine

            if let error = model.saveError {
                Text(error)
                    .font(CypressFont.body125)
                    .foregroundStyle(CypressColor.Dark.accentAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, VisitMetrics.Camera.trayPadding)
        .padding(.top, VisitMetrics.Camera.trayPadding)
        .padding(.bottom, VisitMetrics.Camera.trayBottom)
        .background(CypressColor.Dark.bgCameraTray)
    }

    private var noteField: some View {
        TextField(
            "",
            text: $model.note,
            prompt: Text("Anything worth remembering?")
                .foregroundColor(CypressColor.Dark.textFaint),
            axis: .vertical
        )
        .font(CypressFont.body145)
        .foregroundStyle(CypressColor.Dark.textPrimary)
        .tint(CypressColor.Dark.accentMint)
        .lineLimit(1...3)
        .padding(.vertical, VisitMetrics.Camera.notePaddingV)
        .padding(.horizontal, VisitMetrics.Camera.notePaddingH)
        .frame(minHeight: VisitMetrics.Camera.noteMinHeight, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .fill(CypressColor.Dark.surfaceCardAlt)
        }
        .overlay {
            RoundedRectangle(cornerRadius: CypressRadius.control, style: .continuous)
                .strokeBorder(CypressColor.Dark.borderCamera, lineWidth: CypressSpacing.Component.hairline)
        }
    }

    @ViewBuilder
    private var phenologyChips: some View {
        if let species = model.species {
            HStack(spacing: VisitMetrics.Camera.chipGap) {
                // D5, enforced by the component itself: `Chip.phenology(_:for:isOn:)` renders
                // nothing for a tag outside `species.availablePhenologyTags`, and there is no
                // String initializer that could get around it. An evergreen is never asked about
                // fall colour.
                ForEach(model.availablePhenologyTags, id: \.self) { tag in
                    Chip.phenology(
                        tag,
                        for: species,
                        isOn: model.selectedTags.contains(tag),
                        action: { model.toggle(tag) }
                    )
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var logVisitButton: some View {
        // "the prototype gates `Log visit` on having snapped a photo" — both visually and
        // functionally (PROTOTYPE-FLOW §1.6.1). SCREENS.md marks the disabled styling NOT
        // SPECIFIED; the prototype's own `logBtnStyle` supplies it — fill `#26332A`, label
        // `#5F6F61`. The label is `Dark.textFaint` exactly; the fill has no token of its own, so
        // the nearest documented dark surface (`Dark.surfaceThumb`) stands in rather than a
        // literal being introduced for a state the spec never drew.
        Group {
            if model.canLogVisit {
                PrimaryButton("Log visit", style: .camera) {
                    Task {
                        if let receipt = await model.logVisit() { onSaved(receipt) }
                    }
                }
            } else {
                Text(model.isSaving ? "Saving…" : "Log visit")
                    .font(CypressFont.body16ExtraBold)
                    .foregroundStyle(CypressColor.Dark.textFaint)
                    .frame(maxWidth: .infinity)
                    .padding(CypressSpacing.Component.buttonPadding)
                    .background {
                        RoundedRectangle(cornerRadius: CypressRadius.cardSm, style: .continuous)
                            .fill(CypressColor.Dark.surfaceThumb)
                    }
                    .accessibilityLabel("Log visit, unavailable until you take a photo")
            }
        }
    }

    private var offlineLine: some View {
        // SCREENS 04 draws `No signal · saved to outbox, syncs automatically`. Nothing in the app
        // measures signal, and claiming there is none would be the same class of untruth as
        // "sent to the city" (ARCHITECTURE §5.4). What is always true is the order of operations,
        // which is also the reassurance the line exists to give.
        HStack(spacing: VisitMetrics.Camera.chipGap) {
            Circle()
                .fill(CypressColor.Dark.accentAmber)
                .frame(width: VisitMetrics.Camera.offlineDot, height: VisitMetrics.Camera.offlineDot)
            Text("Saved to your outbox first · syncs on its own")
                .font(CypressFont.body125)
                .foregroundStyle(CypressColor.Dark.textMuted)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shapes

/// One of the four 32×32 L-brackets, `border-radius: 8px` on its outer corner only.
struct VisitFramingCorner: Shape {

    enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }
    }

    let corner: Corner

    func path(in rect: CGRect) -> Path {
        let radius = CypressRadius.framingCorner
        var path = Path()

        switch corner {
        case .topLeading:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .topTrailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                control: CGPoint(x: rect.maxX, y: rect.minY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomLeading:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX + radius, y: rect.maxY),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomTrailing:
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        return path
    }
}

/// The camera's ✕. **NOT SPECIFIED** as a glyph in SCREENS.md; the prototype draws a ✕ top-left.
struct VisitCloseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

/// 68×68 white circle with a 6pt `rgba(255,255,255,.35)` ring.
struct VisitShutterButton: View {
    let isLibrary: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(VisitColor.shutterFill)
            if isLibrary {
                // A library shutter has to read as "pick a photo", not "take one".
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: VisitMetrics.Camera.closeGlyph, weight: .semibold))
                    .foregroundStyle(CypressColor.ctaCameraLabel)
            }
        }
        .frame(width: VisitMetrics.Camera.shutterDiameter, height: VisitMetrics.Camera.shutterDiameter)
        .overlay {
            Circle()
                .strokeBorder(VisitColor.shutterRing, lineWidth: VisitMetrics.Camera.shutterRingWidth)
                .frame(
                    width: VisitMetrics.Camera.shutterDiameter + VisitMetrics.Camera.shutterRingWidth * 2,
                    height: VisitMetrics.Camera.shutterDiameter + VisitMetrics.Camera.shutterRingWidth * 2
                )
        }
    }
}
