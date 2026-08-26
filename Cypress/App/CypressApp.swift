import SwiftUI

@main
struct CypressApp: App {

    @State private var model = AppModel()

    init() {
        // Belt and braces: the fonts are also declared in Info.plist's UIAppFonts, but registering
        // through CoreText makes the failure loud instead of silently falling back to San Francisco.
        _ = CypressFont.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch model.phase {
                case .booting:
                    ProgressView().task { await model.boot() }
                case .ready(let data):
                    // Identity-keyed to the store instance: after `AppModel.reboot()` (an
                    // inventory switch) every `@State` model built from the old layer must be
                    // rebuilt, and `@State` survives a plain re-init of an identical view.
                    RootView(
                        data: data,
                        downloads: model.downloads,
                        downloadService: model.downloadService,
                        onInventoryChange: { model.reboot() }
                    )
                    .id(ObjectIdentifier(data.store))
                case .failed(let reason):
                    ScrollView {
                        Text(reason)
                            .font(.footnote.monospaced())
                            .padding()
                    }
                }
            }
            .tint(CypressColor.canopy)
        }
        // ══════════════════════════════════════════════════════════════════════════════════════
        // **The half of a background download that has no screen in it.**
        //
        // A city pack finishes while the app is suspended, or after the system has terminated it
        // outright. iOS then launches this process — with no window, no scene on screen, and
        // nothing having asked for one — purely to hand the session its events, and it holds the
        // app awake only until this closure returns. `AppModel.init` has already re-created the
        // session under the same identifier by the time this runs, which is the ordering the whole
        // mechanism rests on: the events are delivered to a session that exists, or not at all.
        //
        // What the await covers is not the delivery but the *work*: `awaitBackgroundEvents` returns
        // once `urlSessionDidFinishEvents` has fired **and** the service has finished hashing and
        // installing the file. Returning on the first alone would report finished with the reader's
        // 199 MB still in a staging directory, and the app can be suspended the instant this
        // returns.
        //
        // A Scene modifier rather than an `AppDelegate`'s
        // `application(_:handleEventsForBackgroundURLSession:)`: this app has no delegate, and
        // adding one to reach a callback SwiftUI already exposes would be a second lifecycle to
        // keep in agreement with the first.
        // ══════════════════════════════════════════════════════════════════════════════════════
        .backgroundTask(.urlSession(CityDownloadService.backgroundSessionIdentifier)) {
            await model.downloadService.awaitBackgroundEvents()
        }
    }
}
