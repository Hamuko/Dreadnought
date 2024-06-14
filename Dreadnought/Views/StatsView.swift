import SwiftUI

struct StatGridTitle: View {
    var text: String
    
    var body: some View {
        GridRow {
            Text(text)
                .fontWeight(.bold)
                .gridCellColumns(2)
                .frame(maxWidth: .infinity, alignment: .center)
                .gridCellUnsizedAxes(.horizontal)
        }
    }
}

struct StatsView: View {
    @EnvironmentObject var client: TorrentClient
    
    var allTimeRatio: Double { Double(client.allTimeUpload) / Double(client.allTimeDownload) }
    var sessionRatio: Double { Double(client.sessionUpload) / Double(client.sessionDownload) }

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 15) {
            StatGridTitle(text: "Lifetime")
            GridRow {
                Text("Upload")
                Text(FilesizeFormatStyle().format(client.allTimeUpload))
            }
            GridRow {
                Text("Download")
                Text(FilesizeFormatStyle().format(client.allTimeDownload))
            }
            GridRow {
                Text("Ratio")
                Text(RatioFormatStyle().format(allTimeRatio))
            }

            Divider().gridCellUnsizedAxes(.horizontal)

            StatGridTitle(text: "Session")
            GridRow {
                Text("Upload")
                Text(FilesizeFormatStyle().format(client.sessionUpload))
            }
            GridRow {
                Text("Download")
                Text(FilesizeFormatStyle().format(client.sessionDownload))
            }
            GridRow {
                Text("Ratio")
                Text(RatioFormatStyle().format(sessionRatio))
            }

            GridRow {
                Text("Waste")
                Text(FilesizeFormatStyle().format(client.sessionWaste))
            }
            GridRow {
                Text("Connected peers")
                Text(client.connectedPeers, format: .number)
            }

            Divider().gridCellUnsizedAxes(.horizontal)

            StatGridTitle(text: "Cache")
            GridRow {
                Text("Read cache hits")
                Text(client.readCacheHits, format: .percent)
            }
            GridRow {
                Text("Total buffer size")
                Text(FilesizeFormatStyle().format(client.totalBufferSize))
            }

            Divider().gridCellUnsizedAxes(.horizontal)

            StatGridTitle(text: "Performance")
            GridRow {
                Text("Write cache overload")
                Text(client.writeCacheOverload, format: .percent)
            }
            GridRow {
                Text("Read cache overload")
                Text(client.readCacheOverload, format: .percent)
            }
            GridRow {
                Text("Queued I/O jobs")
                Text(client.queuedIOJobs, format: .number)
            }
            GridRow {
                Text("Average time in queue")
                Text(String(format: "%d ms", client.averageQueueTime))
            }
            GridRow {
                Text("Total queue size")
                Text(FilesizeFormatStyle().format(client.totalQueueSize))
            }
        }
        .padding()
        .frame(width: 250, height: 380)
    }
}

#Preview {
    @State var client = TorrentClient()
    client.allTimeDownload = 197912819680
    client.allTimeUpload = 1834422655961
    client.sessionUpload = 499025
    client.sessionWaste = 1024
    client.connectedPeers = 12
    client.totalBufferSize = 131234
    return StatsView().environmentObject(client)
}
