import SwiftUI

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
        WindowGroup {
            ContentView().environmentObject(self.client)
        }
    }
}

class DreadnoughtAppDelegate: NSObject, NSApplicationDelegate {
    weak var client: TorrentClient?

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            self.client?.addTorrent(url: url)
        }
    }
}
