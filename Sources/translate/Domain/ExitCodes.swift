import Foundation

enum ExitCodeMap: Int32 {
    case success = 0
    case runtimeError = 1
    case invalidArguments = 2
    case aborted = 3
}
