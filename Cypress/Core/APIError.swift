import Foundation

/// The BUILD-PLAN §6 error taxonomy, verbatim.
///
/// The wire shape is always `{error: {code, message, retryable}}`. The `code` strings below are
/// the raw values; `retryable` is a property of the code itself so a caller never has to trust a
/// server field to decide whether to keep an outbox item alive (BUILD-PLAN §6, ARCHITECTURE §4).
public enum APIError: String, Error, Codable, Sendable, CaseIterable {
    case unauthorized = "unauthorized"
    case forbidden = "forbidden"
    case notFound = "not_found"
    case validationFailed = "validation_failed"
    case conflict = "conflict"
    case moderationRejected = "moderation_rejected"
    case rateLimited = "rate_limited"
    case serverError = "server_error"

    /// Whether an outbox item that hit this error should be retried by the backoff schedule.
    ///
    /// Only transient, server-side conditions are retryable. `conflict` is *not*: the proximity
    /// dedupe on `POST /trees` returns it with a candidate list the user must resolve
    /// (BUILD-PLAN §6), and re-sending would not change the answer.
    public var retryable: Bool {
        switch self {
        case .rateLimited, .serverError:
            return true
        case .unauthorized, .forbidden, .notFound, .validationFailed, .conflict, .moderationRejected:
            return false
        }
    }

    /// The `code` string as it appears on the wire. Identical to `rawValue`; named for readability
    /// at call sites that are decoding an envelope.
    public var code: String { rawValue }
}

extension APIError {
    /// The decoded `{error: {code, message, retryable}}` body (BUILD-PLAN §6).
    ///
    /// An unknown `code` decodes to `.serverError` rather than throwing, so a server that grows a
    /// new code cannot brick an old client. The server's `retryable` flag is retained but
    /// `resolvedRetryable` prefers the local taxonomy, which is the binding one.
    public struct Envelope: Codable, Sendable, Hashable {
        public let error: APIError
        public let message: String
        public let serverRetryable: Bool?

        public init(error: APIError, message: String, serverRetryable: Bool? = nil) {
            self.error = error
            self.message = message
            self.serverRetryable = serverRetryable
        }

        public var resolvedRetryable: Bool { error.retryable }

        private enum RootKeys: String, CodingKey { case error }
        private enum ErrorKeys: String, CodingKey { case code, message, retryable }

        public init(from decoder: Decoder) throws {
            let root = try decoder.container(keyedBy: RootKeys.self)
            let nested = try root.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error)
            let code = try nested.decode(String.self, forKey: .code)
            self.error = APIError(rawValue: code) ?? .serverError
            self.message = try nested.decodeIfPresent(String.self, forKey: .message) ?? ""
            self.serverRetryable = try nested.decodeIfPresent(Bool.self, forKey: .retryable)
        }

        public func encode(to encoder: Encoder) throws {
            var root = encoder.container(keyedBy: RootKeys.self)
            var nested = root.nestedContainer(keyedBy: ErrorKeys.self, forKey: .error)
            try nested.encode(error.rawValue, forKey: .code)
            try nested.encode(message, forKey: .message)
            try nested.encode(serverRetryable ?? error.retryable, forKey: .retryable)
        }
    }
}
