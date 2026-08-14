//
//  SessionTransport.swift
//  Cypress — Data/Auth
//
//  Spec §5.8's fix, and it is one paragraph long:
//
//  > "Both files are correct alone. The fix is at the transport: a 401 is a fact about the session,
//  > not about the item, so `RemoteAPI` refreshes once and replays the batch; a failed refresh fails
//  > the batch as a transport failure, which `OutboxQueue.drain` already handles by keeping every
//  > item alive on the backoff. `unauthorized` should reach an outbox item only when the item
//  > genuinely is not this identity's to send, which is what the copy already means."
//
//  Everything in this file is that sentence made mechanical. The one thing it adds is the arithmetic
//  of "once": one rotation, one replay, and a second 401 is still the session — never the item.
//

import Foundation

/// A request path that attaches a credential and keeps 401s away from the caller.
///
/// A protocol so `RemoteAPI` can be given a scripted one in tests and the live one in the app, and
/// so the thing 2b builds against is a seam rather than a concrete type (spec §3.2: the
/// session-owning type "is injected into `RemoteAPI`").
public protocol AuthorizedTransport: Sendable {
    /// Sends `request` with a credential attached.
    ///
    /// - Returns: the 2xx body.
    /// - Throws: an `APIError` for anything the taxonomy covers **except** a session failure, which
    ///   is a `SessionError` and carries no code — see this file's header.
    func send(_ request: URLRequest) async throws -> Data
}

/// The live one: `AppSession` for the credential, one `AuthHTTP` for the wire.
public struct SessionTransport: AuthorizedTransport {

    private let session: AppSession
    private let http: any AuthHTTP

    public init(session: AppSession, http: any AuthHTTP = URLSession.shared) {
        self.session = session
        self.http = http
    }

    public func send(_ request: URLRequest) async throws -> Data {
        let credential = try await session.authorization()
        let (data, response) = try await http.send(authorized(request, with: credential))

        guard response.statusCode == 401 else {
            return try body(data, response)
        }

        // **One rotation.** `AppSession.reauthorize(after:)` is single-flight and returns whatever
        // another caller already rotated to, so a batch and a screen hitting 401 together cost one
        // refresh rather than two — which matters because the service revokes a session family when
        // a refresh token is presented twice.
        //
        // A failure here is `SessionError.refreshFailed`, which is not an `APIError`, so an outbox
        // item that was riding on this request keeps its place in the queue.
        let replacement = try await session.reauthorize(after: credential)
        let (replayData, replayResponse) = try await http.send(authorized(request, with: replacement))

        guard replayResponse.statusCode != 401 else {
            // A fresh credential refused. Still the session — `server/README.md`: "A 401 means the
            // session, never the item… An item that genuinely is not this identity's to send is
            // `forbidden`." Throwing `.unauthorized` here is precisely the defect §5.8 designs out,
            // so this is the one place the temptation has to be refused in writing.
            throw SessionError.sessionRejected
        }
        return try body(replayData, replayResponse)
    }

    private func authorized(_ request: URLRequest, with credential: Authorization) -> URLRequest {
        var authorized = request
        authorized.setValue("Bearer \(credential.bearer)", forHTTPHeaderField: "Authorization")
        return authorized
    }

    private func body(_ data: Data, _ response: HTTPURLResponse) throws -> Data {
        guard (200...299).contains(response.statusCode) else {
            throw AuthResponse.error(data: data)
        }
        return data
    }
}
