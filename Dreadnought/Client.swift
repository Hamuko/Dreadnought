import Foundation
import CryptoKit
import OSLog
import Alamofire

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
    var addedOn: Date
    var state: TorrentState

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
        state: TorrentState
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
        Logger.torrentClient.debug("Authenticating on \(url)")
        DispatchQueue.main.async {
            self.authenticationState = .authenticating
        }
        let parameters = ["username": username, "password": password]
        AF.request(url, method: .post, parameters: parameters, encoder: URLEncodedFormParameterEncoder.default).response { response in
            if let response = response.response {
                if response.statusCode == 403 {
                    Logger.torrentClient.error("User is IP banned for too many failed attempts")
                    DispatchQueue.main.async {
                        self.authenticationState = .banned
                    }
                    return
                }
                if let cookie = response.headers["Set-Cookie"] {
                    self.cookies = cookie.components(separatedBy: ";")[0]
                    self.start()
                    UserDefaults.standard.setValue(self.cookies, forKey: PreferenceNames.clientCookie)
                    UserDefaults.standard.setValue(self.baseURL?.absoluteString, forKey: PreferenceNames.serverURL)
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
    }

    func loadPreferences() {
        if let clientCookie = UserDefaults.standard.string(forKey: PreferenceNames.clientCookie) {
            Logger.torrentClient.debug("Loaded client cookie from preferences.")
            self.cookies = clientCookie
            self.authenticationState = .authenticated
        }
        if let serverURL = UserDefaults.standard.string(forKey: PreferenceNames.serverURL) {
            Logger.torrentClient.debug("Loaded base URL from preferences.")
            self.baseURL = URL(string: serverURL)
        }
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
        guard let url = baseURL?.appending(path: "api/v2/sync/maindata"), let cookie = self.cookies else {
            self.keepUpdating = false
            DispatchQueue.main.async {
                self.authenticationState = .unauthenticated
            }
            return
        }
        let headers: HTTPHeaders = ["Cookie": cookie]
        let response = await AF.request(url, parameters: ["rid": self.rid], headers: headers)
            .serializingDecodable(MainData.self)
            .response

        if let error = response.error {
            Logger.torrentClient.fault("Received error on update: \(error)")
            return
        }

        if let httpResponse = response.response {
            if httpResponse.statusCode == 403 {
                Logger.torrentClient.error("Not authenticated")
                self.keepUpdating = false
                DispatchQueue.main.async {
                    self.authenticationState = .unauthenticated
                }
            }
        }

        switch response.result {
            case .success(let mainData):
                self.processMainData(mainData: mainData)
            case .failure(let error):
                Logger.torrentClient.error("Could not decode main data: \(error)")
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

        let categoryUpdate: Set<String> = mainData.categories?.keys.reduce(into: []) { (result, category) in
            result.insert(category)
        } ?? []
        var torrentUpdate: [String: Torrent] = [:]

        if mainData.fullUpdate {
            Logger.torrentClient.info("Received a full update")
            torrentUpdate = mainData.torrents.reduce(into: [:]) { (result, element) in
                result[element.key] = Torrent(hash: element.key, data: element.value)
            }
        } else {
            for (hash, data) in mainData.torrents {
                if var torrent = self.torrents[hash] {
                    torrent.update(data: data)
                    torrentUpdate[hash] = torrent
                } else {
                    torrentUpdate[hash] = Torrent(hash: hash, data: data)
                }
            }
        }

        RunLoop.main.perform {
            self.downloadSpeed = mainData.serverState.downloadSpeed
            self.uploadSpeed = mainData.serverState.uploadSpeed

            if let connectionStatus = mainData.serverState.connectionStatus {
                self.connectionStatus = connectionStatus
            }

            if mainData.fullUpdate {
                // Full updates need to completely replace the existing data or already-removed items may be retained.
                self.categories = categoryUpdate
                self.torrents = torrentUpdate
            } else {
                self.categories.formUnion(categoryUpdate)

                self.torrents.merge(torrentUpdate) { _, new in new }
                for hash in mainData.torrentsRemoved {
                    Logger.torrentClient.debug("Removing torrent \(hash)")
                    self.torrents.removeValue(forKey: hash)
                }
            }
        }
    }
    
    func setCategory(hashes: Set<String>, category: String) {
        guard let url = baseURL?.appending(path: "api/v2/torrents/setCategory"), let cookie = self.cookies else {
            return
        }
        let headers: HTTPHeaders = ["Cookie": cookie]
        let parameters = ["hashes": hashes.joined(separator: "|"), "category": category]
        AF.request(url, method: .post, parameters: parameters, encoder: URLEncodedFormParameterEncoder.default, headers: headers).response { response in
            switch response.response?.statusCode {
                case 200: Logger.torrentClient.info("Successfully set category to \"\(category)\"")
                case 400: Logger.torrentClient.error("Unknown error while setting category")
                case 409: Logger.torrentClient.warning("No such category \"\(category)\"")
                default: break
            }
        }
    }
}
