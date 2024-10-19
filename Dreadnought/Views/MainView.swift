import SwiftUI

typealias TorrentSelection = Set<Torrent.ID>

enum Filter: Hashable {
    case category(CategoryFilter)
    case state(StateFilter)
}

enum StateFilter: String, CaseIterable, Hashable {
    case all = "All"
    case downloading = "Downloading"
    case seeding = "Seeding"
    case completed = "Completed"
    case resumed = "Resumed"
    case stopped = "Stopped"
    case active = "Active"
    case inactive = "Inactive"
    case stalled = "Stalled"
    case stalledDL = "Stalled downloading"
    case stalledUP = "Stalled seeding"
    case checking = "Checking"
    case errored = "Errored"
}

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

struct StatusNavigationLink: View {
    var state: StateFilter

    var imageName: String {
        switch state {
            case .all: "shuffle"
            case .downloading: "arrow.down"
            case .seeding: "arrow.up"
            case .completed: "checkmark"
            case .resumed: "play"
            case .stopped: "stop"
            case .active: "arrow.up.arrow.down"
            case .inactive: "clock.arrow.2.circlepath"
            case .stalled: "arrow.down.left.arrow.up.right"
            case .stalledDL: "arrow.down.left"
            case .stalledUP: "arrow.up.right"
            case .checking: "arrow.triangle.2.circlepath"
            case .errored: "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        NavigationLink(value: Filter.state(state)) {
            HStack(alignment: .center, spacing: 5) {
                Image(systemName: imageName)
                    .fontWeight(.medium)
                    .font(.system(size: 14))
                    .frame(width: 19, alignment: .center)
                Text(state.rawValue)
            }
        }
    }
}

struct TorrentView: View {
    @EnvironmentObject var client: TorrentClient

    @State var search = ""
    @State var categoryFilter = CategoryFilter.all
    @State var stateFilter = StateFilter.all

    var needsAuthentication: Bool { client.authenticationState != .authenticated }

    var body: some View {
        let torrentView = TorrentList(categoryFilter: $categoryFilter, search: $search, stateFilter: $stateFilter)
            .environmentObject(client)

        let selectedFilters = Binding<Set<Filter>>(get: {
            [Filter.category(categoryFilter), Filter.state(stateFilter)]
        }, set: { newFilter in
            switch newFilter.first {
                case .category(let category):
                    self.categoryFilter = category
                case .state(let state):
                    self.stateFilter = state
                case .none: break
            }
        })

        NavigationSplitView {
            List(selection: selectedFilters) {
                Section(header: Text("Status")) {
                    ForEach(StateFilter.allCases, id: \.self) { state in
                        StatusNavigationLink(state: state)
                    }
                }
                Section(header: Text("Categories")) {
                    NavigationLink(value: Filter.category(CategoryFilter.all)) {
                        Text("All")
                    }
                    NavigationLink(value: Filter.category(CategoryFilter.none)) {
                        Text("Uncategorized")
                    }
                    ForEach(client.categories.sorted(), id: \.self) { category in
                        NavigationLink(value: Filter.category(CategoryFilter.specific(category))) {
                            Text(category)
                        }
                    }
                }
            }
        } detail: {
            torrentView
        }
        .searchable(text: $search)
        .sheet(isPresented: $client.authenticationState.needsAuthentication) {
            LoginView().environmentObject(client)
        }
    }
}

class TorrentActions: ObservableObject {
    @Published var torrentsPendingDeletion: TorrentSelection?
    @Published var torrentsPendingRemoval: TorrentSelection?
    
    var showDeleteConfirmation: Bool {
        get {
            guard let pending = torrentsPendingDeletion else {
                return false
            }
            return !pending.isEmpty
        }
        set {
            if newValue == false {
                torrentsPendingDeletion?.removeAll()
            }
        }
    }

    var showRemoveConfirmation: Bool {
        get {
            guard let pending = torrentsPendingRemoval else {
                return false
            }
            return !pending.isEmpty
        }
        set {
            if newValue == false {
                torrentsPendingRemoval?.removeAll()
            }
        }
    }
}

struct TorrentList: View {
    @EnvironmentObject var client: TorrentClient
    
    @AppStorage("TorrentView.columns") private var columnCustomization: TableColumnCustomization<Torrent>

    @State private var selectedTorrents = TorrentSelection()
    @State private var sortOrder = [KeyPathComparator(\Torrent.name)]
    @StateObject private var torrentActions = TorrentActions()

    @Binding var categoryFilter: CategoryFilter
    @Binding var search: String
    @Binding var stateFilter: StateFilter

    var visibleTorrents: [Torrent] {
        client.torrents.compactMap { (hash: String, torrent: Torrent) in torrent }
            .filter { torrent in
                switch stateFilter {
                    case .all:
                        true
                    case .downloading:
                        torrent.state == .downloading
                    case .seeding:
                        torrent.state == .uploading
                    case .completed:
                        torrent.progress == 1.0
                    case .resumed:
                        torrent.state != .stoppedDL && torrent.state != .stoppedUP
                    case .stopped:
                        torrent.state == .stoppedDL || torrent.state == .stoppedUP
                    case .active:
                        torrent.speedDown != 0 || torrent.speedUp != 0
                    case .inactive:
                        torrent.speedDown == 0 && torrent.speedUp == 0
                    case .stalled:
                        torrent.state == .stalledDL || torrent.state == .stalledUP
                    case .stalledDL:
                        torrent.state == .stalledDL
                    case .stalledUP:
                        torrent.state == .stalledUP
                    case .checking:
                        torrent.state == .checkingResumeData || torrent.state == .checkingDL || torrent.state == .checkingUP
                    case .errored:
                        torrent.state == .error
                }
            }
            .filter { torrent in
                switch categoryFilter {
                case .all: true
                case .none: torrent.category == ""
                case .specific(let category): torrent.category == category
                }
            }
            .filter { torrent in
                guard search != "" else { return true }
                return torrent.name.lowercased().contains(search.lowercased())
            }
            .sorted(using: sortOrder)
    }

    var deleteConfirmationText: String {
        guard let pending = torrentActions.torrentsPendingDeletion else {
            return ""
        }
        if pending.count == 1 {
            guard let torrent = client.torrents[pending.first!] else {
                return ""
            }
            return torrent.name
        }
        return "\(pending.count) torrents selected"
    }

    var removeConfirmationText: String {
        guard let pending = torrentActions.torrentsPendingRemoval else {
            return ""
        }
        if pending.count == 1 {
            guard let torrent = client.torrents[pending.first!] else {
                return ""
            }
            return torrent.name
        }
        return "\(pending.count) torrents selected"
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(visibleTorrents, selection: $selectedTorrents, sortOrder: $sortOrder, columnCustomization: $columnCustomization) {
                TableColumn("Name", value: \.name) { torrent in
                    TorrentName(torrent: torrent)
                }
                .width(min: 1)
                .customizationID("name")

                TableColumn("Progress", value: \.progress) { torrent in
                    Text(torrent.progress, format: ProgressFormatStyle())
                }
                .width(min: 1)
                .alignment(.center)
                .customizationID("progress")

                TableColumn("Size", value: \.size) { torrent in
                    Text(torrent.size != 0 ? FilesizeFormatStyle().format(torrent.size) : "–")
                        .foregroundStyle(torrent.size != 0 ? .primary : .secondary)
                }
                .width(min: 1)
                .alignment(.trailing)
                .customizationID("size")

                TableColumn("Download", value: \.speedDown) { torrent in
                    Text(torrent.speedDown, format: TransferSpeedFormatStyle())
                        .foregroundStyle(torrent.speedDown == 0 ? .gray : .primary)
                }
                .width(min: 1)
                .alignment(.trailing)
                .customizationID("downloadSpeed")

                TableColumn("Upload", value: \.speedUp) { torrent in
                    Text(torrent.speedUp, format: TransferSpeedFormatStyle())
                        .foregroundStyle(torrent.speedUp == 0 ? .gray : .primary)
                }
                .width(min: 1)
                .alignment(.trailing)
                .customizationID("uploadSpeed")

                TableColumn("Ratio", value: \.ratio) { torrent in
                    Text(torrent.ratio, format: RatioFormatStyle())
                }
                .width(min: 1)
                .alignment(.trailing)
                .customizationID("ratio")
                
                TableColumn("Category", value: \.category) { torrent in
                    Text(torrent.category)
                }
                .width(min: 1)
                .customizationID("category")

                TableColumn("Tags") { torrent in
                    Text(torrent.tags.joined(separator: ", "))
                }
                .width(min: 1)
                .customizationID("tags")

                TableColumn("Added on", value: \.addedOn) { torrent in
                    Text(torrent.addedOn, format: .dateTime)
                        .help(torrent.addedOn.formatted(.relative(presentation: .numeric, unitsStyle: .wide)))
                }
                .width(min: 1)
                .customizationID("addedOn")
            }
            .focusedValue(\.torrents, selectedTorrents)
            .focusedValue(\.torrentActions, torrentActions)
            .contextMenu(forSelectionType: Torrent.ID.self) { items in
                Button("Resume") {
                    client.resume(hashes: items)
                }
                Button("Stop") {
                    client.stop(hashes: items)
                }
                Button("Force resume") {
                    client.forceResume(hashes: items)
                }

                Divider()
                
                Button("Remove", role: .destructive) {
                    torrentActions.torrentsPendingRemoval = items
                }
                Button("Remove and delete data", role: .destructive) {
                    torrentActions.torrentsPendingDeletion = items
                }

                Divider()

                Menu("Category") {
                    Button("Reset") {
                        client.setCategory(hashes: items, category: "")
                    }
                    Divider()
                    ForEach(client.categories.sorted(), id: \.self) { category in
                        Button(category) {
                            client.setCategory(hashes: items, category: category)
                        }
                    }
                }
            }
            .confirmationDialog("Remove torrent?", isPresented: $torrentActions.showRemoveConfirmation, actions: {
                TorrentRemovalConfirmation(torrents: $torrentActions.torrentsPendingRemoval, delete: false)
            }, message: {
                Text(removeConfirmationText)
            })
            .dialogIcon(Image(systemName: "xmark.circle.fill"))
            .dialogSeverity(.standard)
            
            .confirmationDialog("Remove torrent and delete data?", isPresented: $torrentActions.showDeleteConfirmation, actions: {
                TorrentRemovalConfirmation(torrents: $torrentActions.torrentsPendingDeletion, delete: true)
            }, message: {
                Text(deleteConfirmationText)
            })
            .dialogSeverity(.critical)

            .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, error in
                        guard let url = url else {
                            return
                        }
                        client.addTorrent(file: url)
                    }
                }
                return true
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
    }
}

struct TorrentRemovalConfirmation : View {
    @EnvironmentObject var client: TorrentClient

    @Binding var torrents: Set<Torrent.ID>?

    var delete: Bool

    var buttonTitle: String {
        delete ? "Remove and delete data" : "Remove"
    }

    var body : some View {
        Button(buttonTitle, role: .destructive) {
            if let torrents = torrents {
                client.deleteTorrents(hashes: torrents, deleteFiles: delete)
            }
            torrents = nil
        }
        .keyboardShortcut(KeyEquivalent("D"), modifiers: .command)

        Button("Cancel", role: .cancel) {
            torrents = nil
        }
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
            case .stoppedDL, .stoppedUP: "stop.circle"
            case .stalledDL, .queuedDL: "arrowshape.down.circle"
            case .stalledUP, .queuedUP: "arrowshape.up.circle"
            case .uploading, .forcedUP: "arrowshape.up.circle.fill"
            default: "questionmark.circle"
        }
    }
    var imageColor: AnyShapeStyle {
        switch torrent.state {
            case .allocating, .stoppedDL, .stoppedUP, .stalledDL, .stalledUP: AnyShapeStyle(.secondary)
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
                .foregroundStyle(torrent.state == .stoppedDL || torrent.state == .stoppedUP ? .secondary : .primary)
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

struct MainView: View {
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

#Preview(traits: .fixedLayout(width: 950, height: 600) ) {
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
            state: .uploading,
            tags: []
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
            state: .downloading,
            tags: []
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
            state: .stalledDL,
            tags: []
        ),
    ]
    client.connectionStatus = .connected
    client.downloadSpeed = client.torrents.reduce(0) { $0 + $1.value.speedDown }
    client.uploadSpeed = client.torrents.reduce(0) { $0 + $1.value.speedUp }
    return MainView().environmentObject(client)
}

#Preview() {
    @State var client = TorrentClient()
    client.authenticationState = .unauthenticated
    return LoginView().environmentObject(client)
}
