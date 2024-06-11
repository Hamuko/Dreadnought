import SwiftUI
import OSLog
import UserNotifications

extension FocusedValues {
    struct TorrentSelectionFocusedValueKey: FocusedValueKey {
        typealias Value = TorrentSelection
    }

    struct TorrentActionsFocusedValueKey: FocusedValueKey {
        typealias Value = TorrentActions
    }

    var torrents: TorrentSelection? {
        get { self[TorrentSelectionFocusedValueKey.self] }
        set { self[TorrentSelectionFocusedValueKey.self] = newValue }
    }
    var torrentActions: TorrentActions? {
        get { self[TorrentActionsFocusedValueKey.self] }
        set { self[TorrentActionsFocusedValueKey.self] = newValue }
    }
}

struct TorrentCommands: Commands {
    @FocusedValue(\.torrents) var torrents: TorrentSelection?
    @FocusedValue(\.torrentActions) var torrentActions: TorrentActions?
    
    let client: TorrentClient

    var disabled: Bool { self.torrents?.isEmpty ?? true }

    var body: some Commands {
        CommandMenu("Torrent") {
            Button("Resume") {
                guard let torrents = torrents else { return }
                client.resume(hashes: torrents)
            }
            .disabled(disabled)
            Button("Pause") {
                guard let torrents = torrents else { return }
                client.pause(hashes: torrents)
            }
            .disabled(disabled)
            Button("Force resume") {
                guard let torrents = torrents else { return }
                client.forceResume(hashes: torrents)
            }
            .disabled(disabled)

            Divider()

            Button("Remove") {
                guard let torrents = torrents else { return }
                torrentActions?.torrentsPendingRemoval = torrents
            }
            .disabled(disabled)
            .keyboardShortcut(KeyEquivalent.delete, modifiers: [])

            Button("Remove and delete data") {
                guard let torrents = torrents else { return }
                torrentActions?.torrentsPendingDeletion = torrents
            }
            .disabled(disabled)
            .keyboardShortcut(KeyEquivalent.deleteForward, modifiers: [])
        }
    }
}

@main
struct DreadnoughtApp: App {
    @NSApplicationDelegateAdaptor(DreadnoughtAppDelegate.self) var appDelegate

    let client: TorrentClient

    init() {
        self.client = TorrentClient()
        self.client.loadPreferences()
        self.client.start()
        self.appDelegate.client = self.client
        self.askNotificationSupport()
    }

    var body: some Scene {
        Window("Dreadnought", id: "main") {
            ContentView().environmentObject(self.client)
        }
        .keyboardShortcut("1", modifiers: .command)
        .commands {
            TorrentCommands(client: client)
            CommandGroup(before: .importExport) {
                Button("Make default for magnet links", action: self.makeDefaultMagnetHandler)
            }
        }
    }

    func askNotificationSupport() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                Logger.app.info("Granted permission for notifications")
            } else {
                Logger.app.warning("Permission for notifications not granted: \(error)")
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
