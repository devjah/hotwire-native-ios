import Foundation

/// Errors representing network/connection errors received when attempting to load a page.
/// Wraps URLError to provide full access to iOS error
public struct WebError: LocalizedError, Equatable, Sendable {
    /// The underlying URLError, if available.
    /// This is nil when the error originates from Turbo.js status codes rather than iOS networking.
    public let urlError: URLError?

    /// The error code (from URLError or Turbo.js status code).
    public let errorCode: Int

    /// A description of the error.
    public let message: String

    // MARK: - Helper Properties

    /// Whether the device appears to be offline or has lost connection.
    public var isOffline: Bool {
        guard let code = urlError?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost].contains(code)
    }

    /// Whether the request timed out.
    public var isTimeout: Bool {
        if let urlError {
            return urlError.code == .timedOut
        }
        // Turbo.js status code -1 = timeout
        return errorCode == -1
    }

    /// Whether the server could not be reached.
    public var isConnectionError: Bool {
        guard let code = urlError?.code else { return false }
        return [.cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(code)
    }

    /// Whether this is an SSL/TLS error.
    public var isSSLError: Bool {
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
        } else if isSSLError {
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
            return message
        }
    }

    // MARK: - Initializers

    public init(urlError: URLError) {
        self.urlError = urlError
        self.errorCode = urlError.code.rawValue
        self.message = urlError.localizedDescription
    }

    public init(errorCode: Int, message: String?) {
        self.urlError = nil
        self.errorCode = errorCode
        self.message = message ?? "Network Error"
    }

    // MARK: - Factory Methods

    /// Creates a WebError from any Error (attempts to extract URLError if possible).
    public static func from(_ error: Error) -> WebError {
        if let urlError = error as? URLError {
            return WebError(urlError: urlError)
        }
        return WebError(errorCode: (error as NSError).code, message: error.localizedDescription)
    }

    /// Internal-only: creates a WebError from a Turbo.js status code.
    /// Public callers should use `init(urlError:)` or `init(errorCode:message:)`.
    ///
    /// These are non-HTTP status codes used by Turbo.js to indicate network-level failures:
    /// - 0 = network failure (fetch failed)
    /// - -1 = timeout
    static func from(turboStatusCode: Int) -> WebError {
        let message: String
        switch turboStatusCode {
        case 0:
            message = "Network failure"
        case -1:
            message = "Timeout"
        default:
            message = "Network error"
        }
        return WebError(errorCode: turboStatusCode, message: message)
    }
}
