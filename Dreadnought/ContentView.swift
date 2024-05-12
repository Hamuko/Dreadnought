import SwiftUI

typealias TorrentSelection = Set<Torrent.ID>

enum CategoryFilter {
    case all
    case none
    case specific(String)
}

extension CategoryFilter: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .all:
            hasher.combine(-1)
        case .none:
            hasher.combine(0)
        case .specific(let category):
            hasher.combine(category)
        }
    }
}

extension CategoryFilter: Equatable {
    static func == (lhs: CategoryFilter, rhs: CategoryFilter) -> Bool {
        switch (lhs, rhs) {
        case (.all, .all), (.none, .none):
            return true
        case (.specific(let lhs), .specific(let rhs)):
            return lhs == rhs
        default:
            return false
        }
    }
}

struct TorrentView: View {
    @EnvironmentObject var client: TorrentClient

    @State private var selectedTorrents = TorrentSelection()
    @State private var sortOrder = [KeyPathComparator(\Torrent.name)]
    @State private var categoryFilter = CategoryFilter.all
    
    var needsAuthentication: Bool { client.authenticationState != .authenticated }

    var visibleTorrents: [Torrent] {
        client.torrents.compactMap { (hash: String, torrent: Torrent) in torrent }
            .filter { torrent in
                switch categoryFilter {
                    case .all: true
                    case .none: torrent.category == ""
                    case .specific(let category): torrent.category == category
                }
            }
            .sorted(using: sortOrder)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $categoryFilter) {
                Section(header: Text("Categories")) {
                    NavigationLink(value: CategoryFilter.all) {
                        Text("All")
                    }
                    NavigationLink(value: CategoryFilter.none) {
                        Text("Uncategorized")
                    }
                    ForEach(client.categories.sorted(), id: \.self) { category in
                        NavigationLink(value: CategoryFilter.specific(category)) {
                            Text(category)
                        }
                    }
                }
            }.font(.system(size: 11))
        } detail: {
            VStack(spacing: 0) {
                Table(visibleTorrents, selection: $selectedTorrents, sortOrder: $sortOrder) {
                    TableColumn("Name", value: \.name) { torrent in
                        TorrentName(torrent: torrent)
                    }

                    TableColumn("Progress") { torrent in
                        Text(torrent.progress, format: ProgressFormatStyle())
                    }
                    .width(55)
                    .alignment(.center)

                    TableColumn("Size", value: \.size) { torrent in
                        Text(torrent.size, format: FilesizeFormatStyle())
                    }
                    .width(60)
                    .alignment(.trailing)

                    TableColumn("Download") { torrent in
                        Text(torrent.speedDown, format: TransferSpeedFormatStyle())
                            .foregroundStyle(torrent.speedDown == 0 ? .gray : .primary)
                    }
                    .width(70)
                    .alignment(.trailing)

                    TableColumn("Upload") { torrent in
                        Text(torrent.speedUp, format: TransferSpeedFormatStyle())
                            .foregroundStyle(torrent.speedUp == 0 ? .gray : .primary)
                    }
                    .width(70)
                    .alignment(.trailing)

                    TableColumn("Ratio", value: \.ratio) { torrent in
                        Text(torrent.ratio, format: RatioFormatStyle())
                    }
                    .width(50)
                    
                    TableColumn("Category", value: \.category) { torrent in
                        Text(torrent.category)
                    }
                    TableColumn("Added on", value: \.addedOn) { torrent in
                        Text(torrent.addedOn, format: .dateTime)
                            .help(torrent.addedOn.formatted(.relative(presentation: .numeric, unitsStyle: .wide)))
                    }
                }
                .onKeyPress(.escape) {
                    DispatchQueue.main.async {
                        self.selectedTorrents.removeAll()
                        client.objectWillChange.send()
                    }
                    return .handled
                }
                .frame(maxHeight: .infinity, alignment: .bottomLeading)
                Divider()
                HStack {
                    Spacer()
                    Divider().frame(height: 28)
                    ConnectionStatusIndicator(status: client.connectionStatus)
                    Divider().frame(height: 28)
                    SessionTransferInfo(speed: client.downloadSpeed) {
                        Image(systemName: "arrow.down").foregroundStyle(.secondary)
                    }
                    SessionTransferInfo(speed: client.uploadSpeed) {
                        Image(systemName: "arrow.up").foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 15)
            }
        }.sheet(isPresented: $client.authenticationState.needsAuthentication, content: {
            LoginView().environmentObject(client)
        })
    }
}

struct TorrentName : View {
    var torrent: Torrent
    
    var imageName: String {
        switch torrent.state {
            case .allocating: "externaldrive.fill.badge.timemachine"
            case .checkingResumeData, .checkingDL, .checkingUP, .moving: "arrow.triangle.2.circlepath.circle"
            case .downloading, .forcedDL: "arrowshape.down.circle.fill"
            case .error: "exclamationmark.octagon.fill"
            case .metaDL: "arrow.clockwise.circle"
            case .missingFiles: "exclamationmark.triangle.fill"
            case .pausedDL, .pausedUP: "pause.circle"
            case .stalledDL, .queuedDL: "arrowshape.down.circle"
            case .stalledUP, .queuedUP: "arrowshape.up.circle"
            case .uploading, .forcedUP: "arrowshape.up.circle.fill"
            default: "questionmark.circle"
        }
    }
    var imageColor: AnyShapeStyle {
        switch torrent.state {
            case .allocating, .pausedDL, .pausedUP, .stalledDL, .stalledUP: AnyShapeStyle(.secondary)
            case .error: AnyShapeStyle(.red)
            case .forcedDL, .forcedUP: AnyShapeStyle(.orange)
            case .missingFiles: AnyShapeStyle(.yellow)
            case .queuedDL, .queuedUP: AnyShapeStyle(.tertiary)
            default: AnyShapeStyle(.primary)
        }
    }

    var body : some View {
        HStack(alignment: .center, spacing: 5) {
            Image(systemName: self.imageName)
                .font(.system(size: 14))
                .foregroundStyle(imageColor)

            Text(torrent.name)
                .foregroundStyle(torrent.state == .pausedDL || torrent.state == .pausedUP ? .secondary : .primary)
        }
        .help(torrent.name)
    }
}

struct ConnectionStatusIndicator : View {
    var status: ConnectionStatus
    
    var helpText: String {
        switch status {
            case .connected: "Connected"
            case .firewalled: "Firewalled"
            case .disconnected: "Disconnected"
        }
    }
    var primaryColor: Color {
        switch status {
            case .connected: .secondary
            case .firewalled: .orange
            case .disconnected: .red
        }
    }
    var secondaryColor: HierarchicalShapeStyle {
        switch status {
            case .connected: .secondary
            case .firewalled: .tertiary
            case .disconnected: .tertiary
        }
    }
    var systemName: String {
        switch status {
            case .connected: "network"
            case .firewalled: "network.badge.shield.half.filled"
            case .disconnected: "network.slash"
        }
    }

    var body: some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(primaryColor, secondaryColor)
            .help(helpText)
            .font(.system(size: 16))
            .frame(width: 22, alignment: .center)
    }
}

/// Total transfer speed indicator in the window footer.
struct SessionTransferInfo<Content: View> : View {
    var speed: Int64
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
            Text(speed, format: TransferSpeedFormatStyle())
                .font(.system(size: 11))
                .frame(width: 60, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}

struct ContentView: View {
    var body: some View {
        TorrentView()
    }
}

struct LoginView: View {
    @Environment(\.dismiss) var dismiss

    @State private var url: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    
    @EnvironmentObject var client: TorrentClient

    var canSubmit: Bool { url != "" && URL(string: url) != nil }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                VStack(alignment: .leading) {
                    Text("Log in to qBittorrent.")
                        .font(.system(size: 12, weight: .bold))
                    Text("Enter the complete URL to your qBittorrent Web UI and user details if your server needs authentication.")
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 10)

            Form {
                TextField(text: $url, prompt: Text("URL")) {
                    Text("URL")
                }
                TextField(text: $username, prompt: Text("Username")) {
                    Text("Username")
                }
                SecureField("Password", text: $password, prompt: Text("Password"))
            }

            HStack {
                if client.authenticationState == .authenticating {
                    ProgressView().controlSize(.small)
                } else if client.authenticationState == .banned {
                    Image(systemName: "nosign")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)
                    Text("Banned for too many repeated attempts.")
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Login", action: login)
                .disabled(!canSubmit)
                .keyboardShortcut(.defaultAction)
            }
            .formStyle(.automatic)
        }
        .textFieldStyle(.roundedBorder)
        .frame(width: 450)
        .padding()
        .onAppear() {
            if let url = UserDefaults.standard.string(forKey: PreferenceNames.serverURL) {
                self.url = url
            }
        }
    }

    func login() {
        guard canSubmit else { return }
        client.baseURL = URL(string: url)
        client.auth(username: username, password: password)
    }
}

#Preview(traits: .fixedLayout(width: 900, height: 500) ) {
    let client = TorrentClient()
    client.categories = ["Linux", "Not Linux"]
    client.torrents = [
        "8a686cbe2ccbc04fc3c1c2d6e213fa69090aea36": Torrent(
            hash: "8a686cbe2ccbc04fc3c1c2d6e213fa69090aea36",
            name: "debian-12.5.0-amd64-DVD-1.iso",
            progress: 1,
            size: 4086562816,
            ratio: 2.09,
            speedDown: 0,
            speedUp: 1490124,
            category: "Linux",
            addedOn: Date(timeIntervalSince1970: 1710550279),
            state: .uploading
        ),
        "2aa4f5a7e209e54b32803d43670971c4c8caaa05": Torrent(
            hash: "2aa4f5a7e209e54b32803d43670971c4c8caaa05",
            name: "ubuntu-24.04-desktop-amd64.iso",
            progress: 0.2,
            size: 6114770944,
            ratio: 0.13,
            speedDown: 2222981,
            speedUp: 198453,
            category: "Linux",
            addedOn: Date(timeIntervalSince1970: 1715512279),
            state: .downloading
        ),
        "0852ef544a4694995fcbef7132477c688ded7d9a": Torrent(
            hash: "0852ef544a4694995fcbef7132477c688ded7d9a",
            name: "wikidata-20240101-all.json.gz",
            progress: 0,
            size: 0,
            ratio: 0,
            speedDown: 0,
            speedUp: 0,
            category: "Not Linux",
            addedOn: Date(timeIntervalSince1970: 1715514390),
            state: .stalledDL
        ),
    ]
    client.connectionStatus = .connected
    client.downloadSpeed = client.torrents.reduce(0) { $0 + $1.value.speedDown }
    client.uploadSpeed = client.torrents.reduce(0) { $0 + $1.value.speedUp }
    return ContentView().environmentObject(client)
}

#Preview() {
    @State var client = TorrentClient()
    client.authenticationState = .unauthenticated
    return LoginView().environmentObject(client)
}
