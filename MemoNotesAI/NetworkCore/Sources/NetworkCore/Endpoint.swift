import Foundation

public enum HTTPMethod: String, Sendable {
    case get    = "GET"
    case post   = "POST"
    case put    = "PUT"
    case delete = "DELETE"
}

public enum RequestBody: Sendable {
    case json(any Encodable & Sendable)
    case multipart(MultipartFormData)
    case empty
}

public protocol Endpoint: Sendable {
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var body: RequestBody { get }
}

public extension Endpoint {
    func urlRequest(baseURL: URL) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw NetworkError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        switch body {
        case .empty:
            break
        case .json(let encodable):
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(encodable)
        case .multipart(let form):
            let (data, contentType) = form.encode()
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        }
        return request
    }
}

public enum NetworkError: Error, Sendable {
    case invalidURL
    case missingCredentials
    case httpError(statusCode: Int, data: Data)
    case decodingFailed(Error)
    case rateLimited(retryAfter: TimeInterval?)
}
