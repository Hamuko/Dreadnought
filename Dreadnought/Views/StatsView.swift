import SwiftUI

struct StatsView: View {
    @EnvironmentObject var client: TorrentClient
    
    var allTimeRatio: Double { Double(client.allTimeUpload) / Double(client.allTimeDownload) }
    var sessionRatio: Double { Double(client.sessionUpload) / Double(client.sessionDownload) }

    var body: some View {
        Grid(alignment: .trailing) {
            GridRow {
                Text("Session")
                    .fontWeight(.bold)
                    .gridCellColumns(2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .gridCellUnsizedAxes(.horizontal)
            }
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

            Divider().gridCellUnsizedAxes(.horizontal)

            GridRow {
                Text("All-time")
                    .fontWeight(.bold)
                    .gridCellColumns(2)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .gridCellUnsizedAxes(.horizontal)
            }
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
        }
        .padding()
    }
}

#Preview {
    StatsView()
}
