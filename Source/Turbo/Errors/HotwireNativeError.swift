import Foundation

/// A unified error type for all Hotwire Native errors.
public enum HotwireNativeError: LocalizedError, Equatable {
    /// HTTP status code errors (4xx, 5xx)
    case http(HttpError)

    /// Network/connection errors
    case web(WebError)

    /// Turbo.js loading errors
    case load(LoadError)

    public var errorDescription: String? {
        switch self {
        case .http(let error):
            return error.errorDescription
        case .web(let error):
            return error.errorDescription
        case .load(let error):
            return error.errorDescription
        }
    }

    /// The HTTP status code, if this is an HTTP error.
    public var statusCode: Int? {
        if case .http(let error) = self {
            return error.statusCode
        }
        return nil
    }

    /// The underlying URLError, if this is a web error with one.
    public var urlError: URLError? {
        if case .web(let error) = self {
            return error.urlError
        }
        return nil
    }
}
