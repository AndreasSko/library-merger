import Foundation

func getTempDir() -> String {
    do {
        let temporaryDirectory = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return temporaryDirectory.path
    } catch {
        return FileManager.default.temporaryDirectory.path
    }
}

enum GeneralError: Error {
    case general(message: String)
    case timeout(message: String)
}

extension GeneralError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .timeout(let message), .general(let message):
            return message
        }
    }
}

enum MergeError: Error {
    case notInitialized(message: String)
    case mergeConflict
    case noConflicts
    case error(message: String)
}

extension MergeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notInitialized(let message):
            return message
        case .error(let message):
            return message
        default:
            return ""
        }
    }
}
