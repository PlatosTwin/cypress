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
                    RootView(data: data)
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
    }
}
