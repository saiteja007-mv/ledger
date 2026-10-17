import SwiftUI

@main
struct LedgerApp: App {
    init() {
        KitFont.register()
        // The on-device assistant was removed on 2026-10-14: free the model files (about 1.6 GB) it may have
        // downloaded. ponytail: drop this line once every installed build has run it.
        try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "Models"))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
