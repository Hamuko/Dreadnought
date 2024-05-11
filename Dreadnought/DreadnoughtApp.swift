import SwiftUI

@main
struct DreadnoughtApp: App {
    let client: TorrentClient

    init() {
        self.client = TorrentClient()
        self.client.loadPreferences()
        self.client.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(self.client)
        }
    }
}
