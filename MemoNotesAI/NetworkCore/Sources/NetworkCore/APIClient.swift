import Foundation
import OSLog

private let logger = Logger(subsystem: "com.memonotesai", category: "Network")

/// Concrete HTTP client. Conforms to `NetworkClient` so it can be injected
/// and swapped for a mock in tests.
///
/// - Retry policy: up to 3 attempts with jittered exponential back-off (cap 8 s).
/// - Retried errors: connection lost, not connected, timed-out, -1017 cannotParseResponse,
///   cannotConnectToHost, and HTTP 5xx responses.
/// - Logging: all attempts, errors, and outcomes go through `os.Logger` — no stray `print` calls.
public struct APIClient: NetworkClient {
    private let baseURL: URL
    private let session: URLSession

    private static let maxAttempts = 3

    public init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity        = true
            config.timeoutIntervalForRequest   = 60
            config.timeoutIntervalForResource  = 300
            config.httpShouldUsePipelining     = false
            // Limit concurrent connections to avoid stale HTTP/2 stream races
            // (-1017 cannotParseResponse on keep-alive reuse).
            config.httpMaximumConnectionsPerHost = 1
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - NetworkClient

    public func send<T: Decodable, E: Endpoint>(_ endpoint: E, as type: T.Type) async throws -> T {
        let data = try await sendRaw(endpoint)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Decoding failed for \(String(describing: T.self)): \(error)")
            throw NetworkError.decodingFailed(error)
        }
    }

    public func sendRaw<E: Endpoint>(_ endpoint: E) async throws -> Data {
        var lastError: Error?

        for attempt in 0..<Self.maxAttempts {
            if attempt > 0 {
                let delay = min(pow(2.0, Double(attempt - 1)) + Double.random(in: 0...0.5), 8.0)
                logger.debug("Attempt \(attempt + 1)/\(Self.maxAttempts) — waiting \(String(format: "%.2f", delay))s")
                try await Task.sleep(for: .seconds(delay))
            }

            do {
                // Rebuild the request on every attempt: ensures a fresh URLRequest
                // with no cached connection hint, which is the cure for -1017 on retry.
                var request = try endpoint.urlRequest(baseURL: baseURL)
                let body = request.httpBody
                request.httpBody = nil

                logger.debug("→ \(request.httpMethod ?? "?") \(request.url?.path ?? "")")

                let (data, response): (Data, URLResponse)
                if let body {
                    (data, response) = try await session.upload(for: request, from: body)
                } else {
                    (data, response) = try await session.data(for: request)
                }

                guard let http = response as? HTTPURLResponse else {
                    throw NetworkError.httpError(statusCode: 0, data: data)
                }

                logger.debug("← HTTP \(http.statusCode) (\(data.count) bytes)")

                guard (200..<300).contains(http.statusCode) else {
                    if http.statusCode == 429 {
                        let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                            .flatMap { TimeInterval($0) }
                        logger.warning("Rate-limited. Retry-After: \(retryAfter.map { "\($0)s" } ?? "none")")
                        throw NetworkError.rateLimited(retryAfter: retryAfter)
                    }
                    logger.error("HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "<binary>")")
                    throw NetworkError.httpError(statusCode: http.statusCode, data: data)
                }

                return data

            } catch let urlError as URLError where isRetriableURLError(urlError) {
                logger.warning("[\(attempt + 1)/\(Self.maxAttempts)] Retriable URLError \(urlError.code.rawValue): \(urlError.localizedDescription)")
                lastError = urlError

            } catch let networkError as NetworkError where isRetriableNetworkError(networkError) {
                logger.warning("[\(attempt + 1)/\(Self.maxAttempts)] Retriable NetworkError: \(networkError)")
                lastError = networkError
            }
        }

        logger.error("All \(Self.maxAttempts) attempts exhausted")
        throw lastError ?? NetworkError.httpError(statusCode: 0, data: Data())
    }

    // MARK: - Retry helpers

    private func isRetriableURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut,
             .cannotParseResponse,   // -1017 stale HTTP/2 stream
             .cannotConnectToHost:
            return true
        default:
            return false
        }
    }

    private func isRetriableNetworkError(_ error: NetworkError) -> Bool {
        if case .httpError(let code, _) = error, (500..<600).contains(code) { return true }
        return false
    }
}
