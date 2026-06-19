import Foundation

/// Abstraction over the HTTP transport layer.
/// Use this protocol for dependency injection and testing — inject `any NetworkClient`
/// rather than the concrete `APIClient` type.
public protocol NetworkClient: Sendable {
    /// Send an endpoint and decode the response body into `T`.
    func send<T: Decodable, E: Endpoint>(_ endpoint: E, as type: T.Type) async throws -> T

    /// Send an endpoint and return the raw response bytes.
    /// Use when you need access to the raw data (e.g. binary downloads).
    func sendRaw<E: Endpoint>(_ endpoint: E) async throws -> Data
}

public extension NetworkClient {
    /// Convenience overload — infers `T` from call-site context.
    func send<T: Decodable, E: Endpoint>(_ endpoint: E) async throws -> T {
        try await send(endpoint, as: T.self)
    }
}
