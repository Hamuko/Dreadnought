import Foundation
import CryptoKit
import OSLog
import Alamofire
import UserNotifications

enum ConnectionStatus {
    case connected
    case firewalled
    case disconnected
}

enum ClientAuthentication {
    /// IP ban triggered by consecutive login failures.
    case banned
    /// Missing a base URL and/or a valid cookie.
    case unauthenticated
    /// Authentication request is currently under way.
    case authenticating
    /// Client has a base URL and a valid cookie.
    case authenticated
}

extension ClientAuthentication {
    var needsAuthentication: Bool {
        get { self != .authenticated }
        set { self = newValue ? Self.unauthenticated : Self.authenticated }
    }
}

enum TorrentNotification {
    case downloadFinished
    case errored
    case missingFiles
    case paused
}

class TorrentClient: ObservableObject {
    var baseURL: URL?

    @Published var categories = Set<String>()
    @Published var torrents: [String: Torrent] = [:]
    @Published var allTimeDownload: Int64 = 0
    @Published var allTimeUpload: Int64 = 0
    @Published var sessionDownload: Int64 = 0
    @Published var sessionUpload: Int64 = 0
    @Published var downloadSpeed: Int64 = 0
    @Published var uploadSpeed: Int64 = 0
    @Published var connectionStatus = ConnectionStatus.disconnected
    @Published var authenticationState: ClientAuthentication = .unauthenticated

    private var cookies: String? = nil
    /// Response ID that qBittorrent uses to track state.
    private var rid = 0
    private var keepUpdating = true
    private var updateTask: Task<Void, Never>?
    
    private func addTorrentCallback(response: AFDataResponse<Data?>) {
        if let error = response.error {
            Logger.torrentClient.info("Error when adding torrent: \(error)")
            return
        }
        if let httpResponse = response.response {
            if httpResponse.statusCode == 200 {
                Logger.torrentClient.info("Successfully added torrent")
            } else {
                Logger.torrentClient.warning("Error adding torrent (HTTP \(httpResponse.statusCode)")
            }
        }
    }

    /// Add a torrent from a remote URL.
    func addTorrent(url torrentUrl: URL) {
        guard let url = baseURL?.appending(path: "api/v2/torrents/add"), let cookie = self.cookies else {
            return
        }
        guard let urlData = torrentUrl.absoluteString.data(using: .utf8) else {
            Logger.torrentClient.error("Could not encode URL")
            return
        }
        let headers: HTTPHeaders = ["Cookie": cookie]
        AF.upload(multipartFormData: { multipartFormData in
            multipartFormData.append(urlData, withName: "urls")
        }, to: url, headers: headers).response(completionHandler: self.addTorrentCallback)
    }

    /// Add a torrent from a local file URL.
    func addTorrent(file torrentFileUrl: URL) {
        guard let url = baseURL?.appending(path: "api/v2/torrents/add"), let cookie = self.cookies else {
            return
        }
        let headers: HTTPHeaders = ["Cookie": cookie]
        AF.upload(multipartFormData: { multipartFormData in
            multipartFormData.append(torrentFileUrl, withName: "torrents")
        }, to: url, headers: headers).response(completionHandler: self.addTorrentCallback)
    }

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

    /// Delete torrents from qBittorrent, optionally also deleting the files while at it.
    func deleteTorrents(hashes: Set<String>, deleteFiles: Bool) {
        guard let url = baseURL?.appending(path: "api/v2/torrents/delete"), let cookie = self.cookies else {
            return
        }
        let headers: HTTPHeaders = ["Cookie": cookie]
        let parameters = ["hashes": hashes.joined(separator: "|"), "deleteFiles": deleteFiles ? "true" : "false"]
        AF.request(url, method: .post, parameters: parameters, encoder: URLEncodedFormParameterEncoder.default, headers: headers).response { response in
            if let error = response.error {
                Logger.torrentClient.info("Error when deleted torrent(s): \(error)")
                return
            }
            if let httpResponse = response.response {
                if httpResponse.statusCode == 200 {
                    Logger.torrentClient.info("Successfully deleted torrent(s)")
                } else {
                    Logger.torrentClient.warning("Error deleted torrent(s) (HTTP \(httpResponse.statusCode)")
                }
            }
        }
    }
    
    func forceResume(hashes: Set<String>) {
        guard let url = baseURL?.appending(path: "api/v2/torrents/setForceStart"), let cookie = self.cookies else {
            return
        }
        let headers: HTTPHeaders = ["Cookie": cookie]
        let parameters = ["hashes": hashes.joined(separator: "|"), "value": "true"]
        AF.request(url, method: .post, parameters: parameters, encoder: URLEncodedFormParameterEncoder.default, headers: headers).response { response in
            if let error = response.error {
                Logger.torrentClient.info("Error when pausing torrent(s): \(error)")
                return
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
            .validate()
            .serializingDecodable(MainData.self)
            .response

        if let error = response.error {
            switch error {
                case .responseValidationFailed(reason: .unacceptableStatusCode(code: 403)):
                    Logger.torrentClient.error("Not authenticated")
                    self.keepUpdating = false
                    DispatchQueue.main.async {
                        self.authenticationState = .unauthenticated
                    }
                default:
                    Logger.torrentClient.fault("Received error on update: \(error)")
            }
            return
        }

        switch response.result {
            case .success(let mainData):
                self.processMainData(mainData: mainData)
            case .failure(let error):
                Logger.torrentClient.error("Could not decode main data: \(error)")
        }
    }

    func pause(hashes: Set<String>) {
        guard let url = baseURL?.appending(path: "api/v2/torrents/pause"), let cookie = self.cookies else {
            return
        }
        let headers: HTTPHeaders = ["Cookie": cookie]
        let parameters = ["hashes": hashes.joined(separator: "|")]
        AF.request(url, method: .post, parameters: parameters, encoder: URLEncodedFormParameterEncoder.default, headers: headers).response { response in
            if let error = response.error {
                Logger.torrentClient.info("Error when pausing torrent(s): \(error)")
                return
            }
        }
    }

    /// Update client state from given main data.
    func processMainData(mainData: MainData) {
        self.rid = mainData.rid

        let categoryUpdate: Set<String> = mainData.categories?.keys.reduce(into: []) { (result, category) in
            result.insert(category)
        } ?? []
        var torrentUpdate: [String: Torrent] = [:]
        var notifiableTorrents: [(Torrent, TorrentNotification)] = []

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
                    if data.progress == 1.0 {
                        notifiableTorrents.append((torrent, .downloadFinished))
                    }
                    if data.state != nil {
                        switch torrent.state {
                            case .error:
                                notifiableTorrents.append((torrent, .errored))
                            case .missingFiles:
                                notifiableTorrents.append((torrent, .missingFiles))
                            case .pausedUP:
                                notifiableTorrents.append((torrent, .paused))
                            default: break
                        }
                    }
                } else {
                    torrentUpdate[hash] = Torrent(hash: hash, data: data)
                }
            }
        }

        RunLoop.main.perform {
            self.downloadSpeed = mainData.serverState.downloadSpeed
            self.uploadSpeed = mainData.serverState.uploadSpeed
            if let allTimeDownload = mainData.serverState.allTimeDownload {
                self.allTimeDownload = allTimeDownload
            }
            if let allTimeUpload = mainData.serverState.allTimeUpload {
                self.allTimeUpload = allTimeUpload
            }
            if let sessionDownload = mainData.serverState.sessionDownload {
                self.sessionDownload = sessionDownload
            }
            if let sessionUpload = mainData.serverState.sessionUpload {
                self.sessionUpload = sessionUpload
            }

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

            for (torrent, notificationType) in notifiableTorrents {
                let notificationContent = UNMutableNotificationContent()
                notificationContent.title = switch notificationType {
                    case .downloadFinished: "Torrent finished"
                    case .errored: "Torrent has errored"
                    case .missingFiles: "Torrent is missing files"
                    case .paused: "Torrent paused"
                }
                notificationContent.body = torrent.name
                notificationContent.sound = .default
                let notificationRequest = UNNotificationRequest(identifier: torrent.hash, content: notificationContent, trigger: nil)
                UNUserNotificationCenter.current().add(notificationRequest)
            }
        }
    }

    func resume(hashes: Set<String>) {
        guard let url = baseURL?.appending(path: "api/v2/torrents/resume"), let cookie = self.cookies else {
            return
        }
        let headers: HTTPHeaders = ["Cookie": cookie]
        let parameters = ["hashes": hashes.joined(separator: "|")]
        AF.request(url, method: .post, parameters: parameters, encoder: URLEncodedFormParameterEncoder.default, headers: headers).response { response in
            if let error = response.error {
                Logger.torrentClient.info("Error when pausing torrent(s): \(error)")
                return
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
