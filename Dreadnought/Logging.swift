import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!

    static let app = Logger(subsystem: subsystem, category: "App")
    static let torrentClient = Logger(subsystem: subsystem, category: "TorrentClient")
}
