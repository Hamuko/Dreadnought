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
    /// Torrent is paused and has NOT finished downloading.
    case pausedDL
    /// Torrent is paused and has finished downloading.
    case pausedUP
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
            case "pausedDL": .pausedDL
            case "pausedUP": .pausedUP
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
