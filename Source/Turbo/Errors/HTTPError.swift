import Foundation

/// Errors representing HTTP status codes received from the server.
public enum HTTPError: LocalizedError, Equatable {
    case client(ClientError)
    case server(ServerError)
    case unknownError(statusCode: Int)

    /// The HTTP status code for this error.
    public var statusCode: Int {
        switch self {
        case .client(let error):
            return error.statusCode
        case .server(let error):
            return error.statusCode
        case .unknownError(let code):
            return code
        }
    }

    public var errorDescription: String? {
        switch self {
        case .client(let error):
            return error.errorDescription
        case .server(let error):
            return error.errorDescription
        case .unknownError(let code): 
            return "HTTP Error (\(code))"
        }
    }

    /// Creates an HttpError from an HTTP status code.
    public static func from(statusCode: Int) -> HTTPError {
        if (400...499).contains(statusCode) {
            return .client(ClientError.from(statusCode: statusCode))
        }

        if (500...599).contains(statusCode) {
            return .server(ServerError.from(statusCode: statusCode))
        }

        return .unknownError(statusCode: statusCode)
    }
}

// MARK: - Client Errors (4xx)

extension HTTPError {
    /// Errors representing HTTP client errors in the 400-499 range.
    public enum ClientError: LocalizedError, Equatable {
        case badRequest
        case unauthorized
        case paymentRequired
        case forbidden
        case notFound
        case methodNotAllowed
        case notAcceptable
        case proxyAuthenticationRequired
        case requestTimeout
        case conflict
        case misdirectedRequest
        case unprocessableEntity
        case preconditionRequired
        case tooManyRequests
        case other(statusCode: Int)

        public var statusCode: Int {
            switch self {
            case .badRequest: return 400
            case .unauthorized: return 401
            case .paymentRequired: return 402
            case .forbidden: return 403
            case .notFound: return 404
            case .methodNotAllowed: return 405
            case .notAcceptable: return 406
            case .proxyAuthenticationRequired: return 407
            case .requestTimeout: return 408
            case .conflict: return 409
            case .misdirectedRequest: return 421
            case .unprocessableEntity: return 422
            case .preconditionRequired: return 428
            case .tooManyRequests: return 429
            case .other(let code): return code
            }
        }

        public var errorDescription: String? {
            switch self {
            case .badRequest: return "Bad Request"
            case .unauthorized: return "Unauthorized"
            case .paymentRequired: return "Payment Required"
            case .forbidden: return "Forbidden"
            case .notFound: return "Not Found"
            case .methodNotAllowed: return "Method Not Allowed"
            case .notAcceptable: return "Not Acceptable"
            case .proxyAuthenticationRequired: return "Proxy Authentication Required"
            case .requestTimeout: return "Request Timeout"
            case .conflict: return "Conflict"
            case .misdirectedRequest: return "Misdirected Request"
            case .unprocessableEntity: return "Unprocessable Entity"
            case .preconditionRequired: return "Precondition Required"
            case .tooManyRequests: return "Too Many Requests"
            case .other(let code): return "Client Error (\(code))"
            }
        }

        public static func from(statusCode: Int) -> ClientError {
            switch statusCode {
            case 400: return .badRequest
            case 401: return .unauthorized
            case 402: return .paymentRequired
            case 403: return .forbidden
            case 404: return .notFound
            case 405: return .methodNotAllowed
            case 406: return .notAcceptable
            case 407: return .proxyAuthenticationRequired
            case 408: return .requestTimeout
            case 409: return .conflict
            case 421: return .misdirectedRequest
            case 422: return .unprocessableEntity
            case 428: return .preconditionRequired
            case 429: return .tooManyRequests
            default: return .other(statusCode: statusCode)
            }
        }
    }
}

// MARK: - Server Errors (5xx)

extension HTTPError {
    /// Errors representing HTTP server errors in the 500-599 range.
    public enum ServerError: LocalizedError, Equatable {
        case internalServerError
        case notImplemented
        case badGateway
        case serviceUnavailable
        case gatewayTimeout
        case httpVersionNotSupported
        case other(statusCode: Int)

        public var statusCode: Int {
            switch self {
            case .internalServerError: return 500
            case .notImplemented: return 501
            case .badGateway: return 502
            case .serviceUnavailable: return 503
            case .gatewayTimeout: return 504
            case .httpVersionNotSupported: return 505
            case .other(let code): return code
            }
        }

        public var errorDescription: String? {
            switch self {
            case .internalServerError: return "Internal Server Error"
            case .notImplemented: return "Not Implemented"
            case .badGateway: return "Bad Gateway"
            case .serviceUnavailable: return "Service Unavailable"
            case .gatewayTimeout: return "Gateway Timeout"
            case .httpVersionNotSupported: return "HTTP Version Not Supported"
            case .other(let code): return "Server Error (\(code))"
            }
        }

        public static func from(statusCode: Int) -> ServerError {
            switch statusCode {
            case 500: return .internalServerError
            case 501: return .notImplemented
            case 502: return .badGateway
            case 503: return .serviceUnavailable
            case 504: return .gatewayTimeout
            case 505: return .httpVersionNotSupported
            default: return .other(statusCode: statusCode)
            }
        }
    }
}
