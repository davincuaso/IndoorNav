import Foundation

enum AppError: LocalizedError, Identifiable {
    case mapLoadFailed(name: String, underlying: Error?)
    case mapSaveFailed(underlying: Error?)
    case mapDeleteFailed(name: String, underlying: Error?)
    case mapNotFound(name: String)
    case mapCorrupted(name: String)
    case noMapsAvailable
    case relocalizationTimeout
    case relocalizationFailed
    case sessionFailed(underlying: Error)
    case sessionInterrupted
    case noARFrame
    case arNotSupported

    var id: String {
        switch self {
        case .mapLoadFailed(let name, _): return "mapLoadFailed-\(name)"
        case .mapSaveFailed: return "mapSaveFailed"
        case .mapDeleteFailed(let name, _): return "mapDeleteFailed-\(name)"
        case .mapNotFound(let name): return "mapNotFound-\(name)"
        case .mapCorrupted(let name): return "mapCorrupted-\(name)"
        case .noMapsAvailable: return "noMapsAvailable"
        case .relocalizationTimeout: return "relocalizationTimeout"
        case .relocalizationFailed: return "relocalizationFailed"
        case .sessionFailed: return "sessionFailed"
        case .sessionInterrupted: return "sessionInterrupted"
        case .noARFrame: return "noARFrame"
        case .arNotSupported: return "arNotSupported"
        }
    }

    var errorDescription: String? {
        switch self {
        case .mapLoadFailed(let name, let underlying):
            if let err = underlying {
                return "Failed to load map \"\(name)\": \(err.localizedDescription)"
            }
            return "Failed to load map \"\(name)\"."

        case .mapSaveFailed(let underlying):
            if let err = underlying {
                return "Failed to save map: \(err.localizedDescription)"
            }
            return "Failed to save the map. Please try again."

        case .mapDeleteFailed(let name, _):
            return "Failed to delete map \"\(name)\"."

        case .mapNotFound(let name):
            return "Map \"\(name)\" was not found. It may have been deleted."

        case .mapCorrupted(let name):
            return "Map \"\(name)\" appears to be corrupted and cannot be loaded."

        case .noMapsAvailable:
            return "No saved maps available. Please map a space first."

        case .relocalizationTimeout:
            return "Unable to localize within the expected time. The environment may have changed significantly."

        case .relocalizationFailed:
            return "Failed to localize. Please ensure you're in the mapped area."

        case .sessionFailed(let underlying):
            return "AR session error: \(underlying.localizedDescription)"

        case .sessionInterrupted:
            return "AR session was interrupted. Please return to the app."

        case .noARFrame:
            return "No AR frame available. Please wait for tracking to initialize."

        case .arNotSupported:
            return "ARKit is not supported on this device."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .mapLoadFailed, .mapCorrupted:
            return "Try selecting a different map, or create a new map in Map mode."

        case .mapSaveFailed:
            return "Ensure you have enough storage space and try again."

        case .mapDeleteFailed:
            return "The file may be in use. Try again later."

        case .mapNotFound:
            return "Select a different map or create a new one."

        case .noMapsAvailable:
            return "Switch to Map mode and walk around the space to create a map."

        case .relocalizationTimeout, .relocalizationFailed:
            return "Move slowly and point your device at recognizable features from when you created the map."

        case .sessionFailed:
            return "Try restarting the app. If the problem persists, restart your device."

        case .sessionInterrupted:
            return "Return to the app to resume the AR session."

        case .noARFrame:
            return "Move your device slowly to help establish tracking."

        case .arNotSupported:
            return "This app requires a device with ARKit support."
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .arNotSupported:
            return false
        default:
            return true
        }
    }

    var alertTitle: String {
        switch self {
        case .mapLoadFailed: return "Map Load Error"
        case .mapSaveFailed: return "Save Failed"
        case .mapDeleteFailed: return "Delete Failed"
        case .mapNotFound: return "Map Not Found"
        case .mapCorrupted: return "Corrupted Map"
        case .noMapsAvailable: return "No Maps"
        case .relocalizationTimeout: return "Localization Timeout"
        case .relocalizationFailed: return "Localization Failed"
        case .sessionFailed: return "AR Error"
        case .sessionInterrupted: return "Session Interrupted"
        case .noARFrame: return "Tracking Issue"
        case .arNotSupported: return "Not Supported"
        }
    }
}
