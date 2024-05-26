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

    enum CodingKeys: String, CodingKey {
        case downloadSpeed = "dl_info_speed"
        case uploadSpeed = "up_info_speed"
        case connectionStatus = "connection_status"
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
    }
}
