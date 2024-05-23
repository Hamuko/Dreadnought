import SwiftUI
import OSLog

@main
struct DreadnoughtApp: App {
    @NSApplicationDelegateAdaptor(DreadnoughtAppDelegate.self) var appDelegate

    let client: TorrentClient

    init() {
        self.client = TorrentClient()
        self.client.loadPreferences()
        self.client.start()
        self.appDelegate.client = self.client
    }

    var body: some Scene {
        Window("Dreadnought", id: "main") {
            ContentView().environmentObject(self.client)
        }
        .keyboardShortcut("1", modifiers: .command)
        .commands {
            CommandGroup(before: .importExport) {
                Button("Make default for magnet links", action: self.makeDefaultMagnetHandler)
            }
        }
    }

    /// Register Dreadnought as the default handler for magnet:// URIs.
    func makeDefaultMagnetHandler() {
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "magnet") { error in
            if let error = error {
                Logger.app.warning("Could not register as the default application for magnet URIs: \(error.localizedDescription)")
            } else {
                Logger.app.info("Registered as the default application for magnet URIs")
            }
        }
    }
}

class DreadnoughtAppDelegate: NSObject, NSApplicationDelegate {
    weak var client: TorrentClient?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                self.client?.addTorrent(file: url)
            } else {
                self.client?.addTorrent(url: url)
            }
        }
    }
}
