import Foundation

/// Imported originals and user-visible exports are retained. Only private
/// acquisition snapshots are temporary.
struct BackupFileStore {
    let documentsDirectory: URL?

    init(documentsDirectory: URL? = FileManager.default.urls(
        for: .documentDirectory, in: .userDomainMask).first) {
        self.documentsDirectory = documentsDirectory
    }

    func newExportURL(now: Date = Date()) throws -> URL {
        guard let documentsDirectory else {
            throw CocoaError(.fileNoSuchFile)
        }
        let name = "merged-\(Int(now.timeIntervalSince1970))-\(UUID().uuidString).jwlibrary"
        return documentsDirectory.appendingPathComponent(name)
    }

}

struct BackupShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
