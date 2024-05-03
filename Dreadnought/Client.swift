import Foundation
import CryptoKit
import OSLog

enum ConnectionStatus {
    case connected
    case firewalled
    case disconnected
}

struct Torrent: Identifiable {
    let hash: String
    var size: Int64
    var name: String
    var progress: Double
    var ratio: Double
    var speedDown: Int64
    var speedUp: Int64
    var category: String

    var id: String { hash }

    init(hash: String,
         name: String,
         progress: Double,
         size: Int64,
         ratio: Double,
         speedDown:Int64,
         speedUp:Int64,
         category: String) {
        self.hash = hash
        self.name = name
        self.progress = progress
        self.size = size
        self.ratio = ratio
        self.speedDown = speedDown
        self.speedUp = speedUp
        self.category = category
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
    }

    mutating func update(data: TorrentData) {
        if let progress = data.progress {
            self.progress = progress
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
    }
}

enum ClientAuthentication {
    case banned
    case unauthenticated
    case authenticating
    case authenticated
}

extension ClientAuthentication {
    var needsAuthentication: Bool {
        get { self != .authenticated }
        set { self = newValue ? Self.unauthenticated : Self.authenticated }
    }
}

class TorrentClient: ObservableObject {
    var baseURL: URL?

    @Published var categories = Set<String>()
    @Published var torrents: [String: Torrent] = [:]
    @Published var downloadSpeed: Int64 = 0
    @Published var uploadSpeed: Int64 = 0
    @Published var connectionStatus = ConnectionStatus.disconnected
    @Published var authenticationState: ClientAuthentication = .unauthenticated

    private var cookies: String? = nil
    /// Response ID that qBittorrent uses to track state.
    private var rid = 0
    private var keepUpdating = true
    private var updateTask: Task<Void, Never>?
    
    /// Get a session cookie.
    func auth(username: String, password: String) {
        guard let url = self.baseURL?.appending(path: "api/v2/auth/login") else {
            return
        }
        DispatchQueue.main.async {
            self.authenticationState = .authenticating
        }
        var request = URLRequest(url: url)
        request.httpBody = "username=\(username)&password=\(password)".data(using: .utf8)
        request.httpMethod = "POST"
        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 {
                    Logger.torrentClient.error("User is IP banned for too many failed attempts")
                    DispatchQueue.main.async {
                        self.authenticationState = .banned
                    }
                    return
                }
                if let cookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie") {
                    self.cookies = cookie.components(separatedBy: ";")[0]
                    self.start()
                    DispatchQueue.main.async {
                        self.authenticationState = .authenticated
                    }
                    return
                }
            }
            DispatchQueue.main.async {
                self.authenticationState = .unauthenticated
            }
        }
        Logger.torrentClient.debug("Authenticating on \(url)")
        task.resume()
    }

    func start() {
        self.keepUpdating = true
        self.rid = 0
        self.updateTask = Task(priority: .background) {
            while self.keepUpdating {
                await self.fetchData()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func fetchData() async {
        Logger.torrentClient.debug("Fetching main data from server")
        do {
            guard let request = self.mainDataRequest() else {
                self.keepUpdating = false
                DispatchQueue.main.async {
                    self.authenticationState = .unauthenticated
                }
                return
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 403 {
                    Logger.torrentClient.error("Not authenticated")
                    self.keepUpdating = false
                    DispatchQueue.main.async {
                        self.authenticationState = .unauthenticated
                    }
                }
            }

            guard let mainData = MainData.decode(from: data) else {
                Logger.torrentClient.error("Could not decode main data")
                return
            }
            self.processMainData(mainData: mainData)
        } catch {
            Logger.torrentClient.fault("Received error on update: \(error)")
        }
    }

    func mainDataRequest() -> URLRequest? {
        guard let url = baseURL?.appending(path: "api/v2/sync/maindata") else {
            return nil
        }
        let query = URLQueryItem(name: "rid", value: String(self.rid))
        var request = URLRequest(url: url.appending(queryItems: [query]))
        if let cookie = self.cookies {
            request.allHTTPHeaderFields = ["Cookie": cookie]
        }
        return request
    }

    /// Update client state from given main data.
    func processMainData(mainData: MainData) {
        self.rid = mainData.rid

        let newCategories: Set<String> = mainData.categories?.keys.reduce(into: []) { (result, category) in
            result.insert(category)
        } ?? []

        var updates: [String: Torrent] = [:]
        for (hash, data) in mainData.torrents {
            if var torrent = self.torrents[hash] {
                torrent.update(data: data)
                updates[hash] = torrent
            } else {
                updates[hash] = Torrent(hash: hash, data: data)
            }
        }

        DispatchQueue.main.async {
            self.downloadSpeed = mainData.serverState.downloadSpeed
            self.uploadSpeed = mainData.serverState.uploadSpeed

            if let connectionStatus = mainData.serverState.connectionStatus {
                self.connectionStatus = connectionStatus
            }

            self.categories.formUnion(newCategories)

            self.torrents.merge(updates) { _, new in new }
            for hash in mainData.torrentsRemoved {
                self.torrents.removeValue(forKey: hash)
            }
        }
    }
}
