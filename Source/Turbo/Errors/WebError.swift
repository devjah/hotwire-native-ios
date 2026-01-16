import Foundation

/// Errors representing network/connection errors received when attempting to load a page.
/// Wraps URLError to provide full access to iOS error
public struct WebError: LocalizedError, Equatable {
    /// The underlying URLError, if available.
    /// This is nil when the error originates from Turbo.js status codes rather than iOS networking.
    public let urlError: URLError?

    /// The error code (from URLError or Turbo.js status code).
    public let errorCode: Int

    /// A description of the error.
    public let description: String

    // MARK: - Helper Properties

    /// Whether the device appears to be offline or has lost connection.
    public var isOffline: Bool {
        guard let code = urlError?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost].contains(code)
    }

    /// Whether the request timed out.
    public var isTimeout: Bool {
        // Turbo.js status code -1 = timeout
        return errorCode == URLError.Code.timedOut.rawValue || errorCode == -1
    }

    /// Whether the server could not be reached.
    public var isConnectionError: Bool {
        guard let code = urlError?.code else { return false }
        return [.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(code)
    }

    /// Whether this is an SSL/TLS error.
    public var isSslError: Bool {
        guard let code = urlError?.code else { return false }
        return [
            .secureConnectionFailed,
            .serverCertificateHasBadDate,
            .serverCertificateUntrusted,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .clientCertificateRejected,
            .clientCertificateRequired
        ].contains(code)
    }

    // MARK: - LocalizedError

    public var errorDescription: String? {
        if isConnectionError || isOffline {
            return "Could not connect to the server."
        } else if isTimeout {
            return "The request timed out."
        } else if isSslError {
            return "A secure connection could not be established."
        } else if urlError?.code == .httpTooManyRedirects {
            return "Too many redirects occurred."
        } else if urlError?.code == .badURL {
            return "The URL is invalid."
        } else if let urlError {
            // Fall back to system's localized description for unhandled URLError codes
            // (e.g., ATS, background-session, caching errors)
            return urlError.localizedDescription
        } else {
            // Turbo.js status codes (0, -1) without URLError
            return "A network error occurred."
        }
    }

    // MARK: - Initializers

    public init(urlError: URLError) {
        self.urlError = urlError
        self.errorCode = urlError.code.rawValue
        self.description = urlError.localizedDescription
    }

    public init(errorCode: Int, description: String?) {
        self.urlError = nil
        self.errorCode = errorCode
        self.description = description ?? "Network Error"
    }

    // MARK: - Factory Methods

    /// Creates a WebError from a URLError.
    public static func from(_ urlError: URLError) -> WebError {
        WebError(urlError: urlError)
    }

    /// Creates a WebError from any Error (attempts to extract URLError if possible).
    public static func from(_ error: Error) -> WebError {
        if let urlError = error as? URLError {
            return WebError(urlError: urlError)
        }
        return WebError(errorCode: (error as NSError).code, description: error.localizedDescription)
    }

    /// Creates a WebError from a Turbo.js status code.
    /// These are non-HTTP status codes used by Turbo.js to indicate network-level failures:
    /// - 0 = network failure (fetch failed)
    /// - -1 = timeout
    static func from(turboStatusCode: Int) -> WebError {
        let description: String
        switch turboStatusCode {
        case 0:
            description = "Network failure"
        case -1:
            description = "Timeout"
        default:
            description = "Network error"
        }
        return WebError(errorCode: turboStatusCode, description: description)
    }
}
