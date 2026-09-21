import Foundation

/// Turns an error into something worth putting in the status bar.
///
/// Every message here finishes the sentence "this feed ..." or "this file ...", so a status line
/// reads as English rather than as a stack of nouns. What it replaces is the raw exception text:
/// the underlying failure for a well-formed document that is not a feed is a message about
/// serializers, and for a missing host it is a URL error code, neither of which tells a reader
/// anything they can act on.
public enum ErrorText {
    public static func describe(_ error: Error) -> String {
        switch error {
        case let failure as FeedLoader.HTTPFailure:
            let name = HTTPURLResponse.localizedString(forStatusCode: failure.status)
            return "server said \(failure.status) \(name)"

        case let failure as FeedParser.Failure:
            return failure.description

        case let failure as OpmlParser.Failure:
            return failure.description

        case is XMLSafety.DoctypeRejected:
            return XMLSafety.DoctypeRejected().description

        case is FeedLoader.MalformedURL:
            return "has an address RSS Quick cannot read"

        case is FeedLoader.ResponseTooLarge:
            return "sent more than RSS Quick will read"

        case is CancellationError:
            return "was cancelled"

        case let urlError as URLError:
            switch urlError.code {
            case .timedOut: return "timed out"
            case .cancelled: return "was cancelled"
            case .notConnectedToInternet: return "could not be reached - there is no network"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "could not be reached"
            default: return "could not be reached"
            }

        case let cocoa as CocoaError where cocoa.code == .fileReadNoSuchFile:
            return "could not be found"

        default:
            return error.localizedDescription
        }
    }
}
