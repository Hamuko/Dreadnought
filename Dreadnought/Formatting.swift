import Foundation

/// Filesize formatting in power of 10 (as is customary on macOS).
struct FilesizeFormatStyle: FormatStyle {
    func format(_ value: Int64) -> String {
        if value >= 100_000_000_000 {
            let value = Double(value) / 1_000_000_000
            return String(format: "%.1f GB", value)
        }
        if value >= 1_000_000_000 {
            let value = Double(value) / 1_000_000_000
            return String(format: "%.2f GB", value)
        }
        if value >= 1_000_000 {
            let value = Double(value) / 1_000_000
            return String(format: "%.1f MB", value)
        }
        if value >= 1000 {
            let value = value / 1000
            return String(format: "%d kB", value)
        }
        return String(format: "%d B", value)
    }
}

struct ProgressFormatStyle: FormatStyle {
    func format(_ value: Double) -> String {
        if value == 1 {
            return "100%"
        }
        return String(format: "%.1f%%", (value * 1000).rounded(.down) / 10)
    }
}

struct RatioFormatStyle: FormatStyle {
    func format(_ value: Double) -> String {
        return String(format: "%.2f", value)
    }
}

/// Transfer speed formatting in power of 10 (as is customary on macOS).
struct TransferSpeedFormatStyle: FormatStyle {
    func format(_ value: Int64) -> String {
        if value >= 1000000000 {
            let value = Double(value) / 1000000000
            return String(format: "%.1f GB/s", value)
        }
        if value >= 10_000_000 {
            let value = Double(value) / 1_000_000
            return String(format: "%.1f MB/s", value)
        }
        if value >= 1_000_000 {
            let value = Double(value) / 1_000_000
            return String(format: "%.2f MB/s", value)
        }
        if value >= 1000 {
            let value = value / 1000
            return String(format: "%d kB/s", value)
        }
        return String(format: "%d B/s", value)
    }
}
