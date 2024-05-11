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
                    TableColumn("Name", value: \.name)

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
            category: "Linux"),
        "2aa4f5a7e209e54b32803d43670971c4c8caaa05": Torrent(
            hash: "2aa4f5a7e209e54b32803d43670971c4c8caaa05",
            name: "ubuntu-24.04-desktop-amd64.iso",
            progress: 0.2,
            size: 6114770944,
            ratio: 0.13,
            speedDown: 2222981,
            speedUp: 198453,
            category: "Linux"),
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
