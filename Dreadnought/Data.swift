import Foundation

struct Torrent: Identifiable {
    let hash: String
    var size: Int64
    var name: String
    var progress: Double
    var ratio: Double
    var speedDown: Int64
    var speedUp: Int64
    var category: String
    var addedOn: Date
    var state: TorrentState
    var tags: [String]

    var id: String { hash }

    init(
        hash: String,
        name: String,
        progress: Double,
        size: Int64,
        ratio: Double,
        speedDown:Int64,
        speedUp:Int64,
        category: String,
        addedOn: Date,
        state: TorrentState,
        tags: [String]
    ) {
        self.hash = hash
        self.name = name
        self.progress = progress
        self.size = size
        self.ratio = ratio
        self.speedDown = speedDown
        self.speedUp = speedUp
        self.category = category
        self.addedOn = addedOn
        self.state = state
        self.tags = tags
    }

    init(hash: String, data: TorrentData) {
        self.hash = hash
        self.name = data.name!
        self.progress = data.progress!
        self.size = Int64(data.size!)
        self.ratio = data.ratio!
        self.speedDown = Int64(data.dlspeed!)
        self.speedUp = Int64(data.upspeed!)
        self.category = data.category!
        self.addedOn = Date(timeIntervalSince1970: TimeInterval(data.addedOn!))
        self.state = TorrentState.from(data.state!)
        self.tags = data.tags!.split(separator: ", ").map { String($0) }
    }

    mutating func update(data: TorrentData) {
        if let progress = data.progress {
            self.progress = progress
        }
        if let size = data.size {
            self.size = Int64(size)
        }
        if let ratio = data.ratio {
            self.ratio = ratio
        }
        if let dlspeed = data.dlspeed {
            self.speedDown = Int64(dlspeed)
        }
        if let upspeed = data.upspeed {
            self.speedUp = Int64(upspeed)
        }
        if let category = data.category {
            self.category = category
        }
        if let state = data.state {
            self.state = TorrentState.from(state)
        }
        if let tags = data.tags {
            self.tags = tags.split(separator: ", ").map { String($0) }
        }
    }
}

enum TorrentState {
    /// Torrent is allocating disk space for download.
    case allocating
    /// Same as checkingUP, but torrent has NOT finished downloading.
    case checkingDL
    /// Checking resume data on qBt startup.
    case checkingResumeData
    /// Torrent has finished downloading and is being checked.
    case checkingUP
    /// Torrent is being downloaded and data is being transferred.
    case downloading
    /// Some error occurred, applies to paused torrents.
    case error
    /// Torrent is forced to downloading to ignore queue limit.
    case forcedDL
    /// Torrent is forced to uploading and ignore queue limit.
    case forcedUP
    /// Torrent has just started downloading and is fetching metadata.
    case metaDL
    /// Torrent data files is missing.
    case missingFiles
    /// Torrent is moving to another location.
    case moving
    /// Torrent is stopped and has NOT finished downloading.
    case stoppedDL
    /// Torrent is stopped and has finished downloading.
    case stoppedUP
    /// Queuing is enabled and torrent is queued for download.
    case queuedDL
    /// Queuing is enabled and torrent is queued for upload.
    case queuedUP
    /// Torrent is being downloaded, but no connection were made.
    case stalledDL
    /// Torrent is being seeded, but no connection were made.
    case stalledUP
    /// Unknown status.
    case unknown
    /// Torrent is being seeded and data is being transferred.
    case uploading
}

extension TorrentState {
    static func from(_ from: String) -> Self {
        return switch from {
            case "allocating": .allocating
            case "checkingDL": .checkingDL
            case "checkingResumeData": .checkingResumeData
            case "checkingUP": .checkingUP
            case "downloading": .downloading
            case "error": .error
            case "forcedDL": .forcedDL
            case "forcedUP": .forcedUP
            case "metaDL": .metaDL
            case "missingFiles": .missingFiles
            case "moving": .moving
            case "stoppedDL": .stoppedDL
            case "stoppedUP": .stoppedUP
            case "queuedDL": .queuedDL
            case "queuedUP": .queuedUP
            case "stalledDL": .stalledDL
            case "stalledUP": .stalledUP
            case "unknown": .unknown
            case "uploading": .uploading
            default: .unknown
        }
    }
}
