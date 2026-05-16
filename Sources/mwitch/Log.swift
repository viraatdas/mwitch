import Foundation

/// Tiny diagnostic logger — writes to ~/Library/Logs/mwitch.log so we can see
/// what the (UI-less) app is doing without launching it from a terminal.
final class MwitchLog {
    static let shared = MwitchLog()
    private let url: URL
    private let formatter: DateFormatter
    private let queue = DispatchQueue(label: "dev.mwitch.log")

    private init() {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("mwitch.log")
        formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
    }

    func line(_ msg: String) {
        let stamp = formatter.string(from: Date())
        let text = "[\(stamp)] \(msg)\n"
        queue.async { [url] in
            guard let data = text.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
