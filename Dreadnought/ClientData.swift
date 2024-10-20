import Foundation

struct MainData: Decodable {
    let categories: [String: CategoryData]?
    let torrents: [String: TorrentData]
    let torrentsRemoved: [String]
    let rid: Int
    let serverState: ServerState
    let fullUpdate: Bool
    
    enum CodingKeys: String, CodingKey {
        case categories
        case torrents
        case torrentsRemoved = "torrents_removed"
        case rid
        case serverState = "server_state"
        case fullUpdate = "full_update"
    }
    
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        categories = try? values.decode([String: CategoryData].self, forKey: .categories)
        torrents = try values.decode([String : TorrentData].self, forKey: .torrents)
        torrentsRemoved = (try? values.decode([String].self, forKey: .torrentsRemoved)) ?? []
        rid = try values.decode(Int.self, forKey: .rid)
        serverState = try values.decode(ServerState.self, forKey: .serverState)
        fullUpdate = (try? values.decode(Bool.self, forKey: .fullUpdate)) ?? false
    }

    static func decode(from: Data) -> Self? {
        return try? JSONDecoder().decode(MainData.self, from: from)
    }
}

struct CategoryData: Codable {}

struct TorrentData: Decodable {
    let magnetURI: String?
    let name: String?
    let progress: Double?
    let size: Int?
    let ratio: Double?
    let dlspeed: Int?
    let upspeed: Int?
    let category: String?
    let addedOn: Int?
    let state: String?
    let tags: String?

    enum CodingKeys: String, CodingKey {
        case magnetURI = "magnet_uri"
        case name
        case progress
        case size
        case ratio
        case dlspeed
        case upspeed
        case category
        case addedOn = "added_on"
        case state
        case tags
    }
    
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        magnetURI = (try? values.decode(String.self, forKey: .magnetURI))
        name = (try? values.decode(String.self, forKey: .name))
        progress = (try? values.decode(Double.self, forKey: .progress))
        size = (try? values.decode(Int.self, forKey: .size))
        ratio = (try? values.decode(Double.self, forKey: .ratio))
        dlspeed = (try? values.decode(Int.self, forKey: .dlspeed))
        upspeed = (try? values.decode(Int.self, forKey: .upspeed))
        category = (try? values.decode(String.self, forKey: .category))
        addedOn = try? values.decode(Int.self, forKey: .addedOn)
        state = try? values.decode(String.self, forKey: .state)
        tags = try? values.decode(String.self, forKey: .tags)
    }
}

struct ServerState: Decodable {
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let connectionStatus: ConnectionStatus?

    let allTimeDownload: Int64?
    let allTimeUpload: Int64?
    let sessionDownload: Int64?
    let sessionUpload: Int64?

    let sessionWaste: Int64?
    let connectedPeers: Int64?
    let readCacheHits: Double?
    let totalBufferSize: Int64?
    let writeCacheOverload: Double?
    let readCacheOverload: Double?
    let queuedIOJobs: Int64?
    let averageQueueTime: Int64?
    let totalQueueSize: Int64?

    enum CodingKeys: String, CodingKey {
        case downloadSpeed = "dl_info_speed"
        case uploadSpeed = "up_info_speed"
        case connectionStatus = "connection_status"

        case allTimeDownload = "alltime_dl"
        case allTimeUpload = "alltime_ul"
        case sessionDownload = "dl_info_data"
        case sessionUpload = "up_info_data"

        case sessionWaste = "total_wasted_session"
        case connectedPeers = "total_peer_connections"
        case readCacheHits = "read_cache_hits"
        case totalBufferSize = "total_buffers_size"
        case writeCacheOverload = "write_cache_overload"
        case readCacheOverload = "read_cache_overload"
        case queuedIOJobs = "queued_io_jobs"
        case averageQueueTime = "average_time_queue"
        case totalQueueSize = "total_queued_size"
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        downloadSpeed = (try? values.decode(Int64.self, forKey: .downloadSpeed)) ?? 0
        uploadSpeed = (try? values.decode(Int64.self, forKey: .uploadSpeed)) ?? 0
        connectionStatus = switch try? values.decode(String.self, forKey: .connectionStatus) {
            case "connected":
                ConnectionStatus.connected
            case "firewalled":
                ConnectionStatus.firewalled
            case "disconnected":
                ConnectionStatus.disconnected
            default:
                nil
        }

        allTimeDownload = try? values.decode(Int64.self, forKey: .allTimeDownload)
        allTimeUpload = try? values.decode(Int64.self, forKey: .allTimeUpload)
        sessionDownload = try? values.decode(Int64.self, forKey: .sessionDownload)
        sessionUpload = try? values.decode(Int64.self, forKey: .sessionUpload)

        sessionWaste = try? values.decode(Int64.self, forKey: .sessionWaste)
        connectedPeers = try? values.decode(Int64.self, forKey: .connectedPeers)
        readCacheHits = try? values.decode(Double.self, forKey: .readCacheHits)
        totalBufferSize = try? values.decode(Int64.self, forKey: .totalBufferSize)
        writeCacheOverload = try? values.decode(Double.self, forKey: .writeCacheOverload)
        readCacheOverload = try? values.decode(Double.self, forKey: .readCacheOverload)
        queuedIOJobs = try? values.decode(Int64.self, forKey: .queuedIOJobs)
        averageQueueTime = try? values.decode(Int64.self, forKey: .averageQueueTime)
        totalQueueSize = try? values.decode(Int64.self, forKey: .totalQueueSize)
    }
}
