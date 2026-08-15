//
//  AuthHTTP.swift
//  Cypress — Data/Auth
//
//  The one seam between this layer and the network, and the one place a response body becomes an
//  `APIError`.
//

import Foundation

/// One HTTP round trip.
///
/// A protocol so every test in this folder can script the far side by hand. `URLSession` conforms
/// below; the network is never a test dependency here, for the reason `CityDownloader` states about
/// its own injected session.
public protocol AuthHTTP: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: AuthHTTP {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            // Not `APIError.serverError`: nothing answered, so this is transport, and the
            // distinction is what keeps an outbox item alive (see `SessionError`).
            throw SessionError.malformedResponse
        }
        return (data, http)
    }
}

/// What goes wrong with a *session* rather than with a request.
///
/// **None of these is an `APIError`, and that is the whole point.**
/// `OutboxFailureReason.apiError(from:)` — the type is `OutboxFailureReason`, declared inside
/// `Cypress/Data/Outbox/OutboxViewState.swift`, which is a file and not the type — returns nil for
/// an error it does not recognize, `OutboxRetryPolicy.nextState` reads nil as "no taxonomy opinion",
/// and the item stays `.pending` on the backoff. An `APIError.unauthorized` reaching an outbox item
/// moves it to `.failed` immediately — spec §5.8 and ERRATA **E261** §3, and it is the defect this
/// whole folder is written to design out.
///
/// **What the row would then say has changed, and this comment used to name the old sentence.** It
/// read `prints "Sign in to send this" to somebody who is signed in`. Since the owner's ruling 1 of
/// 2026-08-14 a terminally refused row reads `OutboxFailureReason.refusedTerminally` — "This
/// couldn't be sent." — and the per-code sentence for `unauthorized` is unreachable from an outbox
/// row. The defect is unchanged and is arguably worse dressed this way: the row now says nothing at
/// all about why, to somebody whose session simply needed refreshing.
public enum SessionError: Error, Equatable, CustomStringConvertible {
    /// The refresh could not be performed, or the service refused it. There is no session to send
    /// with; the batch is a transport failure and every item stays alive.
    case refreshFailed
    /// A request came back 401 again after a successful refresh. Still the session, still never the
    /// item — an item that genuinely is not this identity's to send is answered `forbidden`
    /// (`server/README.md`, "Three rules the code will not let you break quietly").
    case sessionRejected
    /// A credential could not be obtained at all — the service refused the registration that would
    /// have minted one. Thrown by `SessionTransport.credential(replacing:)`, which is where a
    /// taxonomy code stops being about the item; `AppSession` itself reports what the service said,
    /// because a caller that asked it directly wants that answer.
    case noCredential
    /// Something answered that was not an HTTP response, or a 2xx body that would not decode.
    case malformedResponse

    public var description: String {
        switch self {
        case .refreshFailed: return "the session could not be refreshed"
        case .sessionRejected: return "the service refused this session after a refresh"
        case .noCredential: return "this device holds no credential to send with"
        case .malformedResponse: return "the service's answer could not be read"
        }
    }
}

/// Turns a non-2xx answer into the taxonomy.
enum AuthResponse {

    /// Decodes `T` from a 2xx body, or throws the `{error: {code, message, retryable}}` the body
    /// carries.
    ///
    /// An error body that will not decode is `.serverError` and not `.malformedResponse`: the
    /// service *did* answer and it answered badly, which is retryable, whereas
    /// `.malformedResponse` on a 2xx means the thing this call was for did not arrive.
    static func decode<T: Decodable>(
        _ type: T.Type,
        data: Data,
        response: HTTPURLResponse
    ) throws -> T {
        guard (200...299).contains(response.statusCode) else {
            throw error(data: data)
        }
        do {
            return try AuthCoding.decoder.decode(T.self, from: data)
        } catch {
            throw SessionError.malformedResponse
        }
    }

    static func error(data: Data) -> APIError {
        guard let envelope = try? AuthCoding.decoder.decode(APIError.Envelope.self, from: data) else {
            return .serverError
        }
        return envelope.error
    }
}
