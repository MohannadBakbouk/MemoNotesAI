import Foundation
import NetworkCore
import PersistenceCore

public struct GroqTranscriptionService: TranscriptionService {
    public let method: TranscriptionMethod = .groq

    private let apiClient: NetworkClient

    public init(apiClient: NetworkClient = APIClient(baseURL: GroqConstants.baseURL)) {
        self.apiClient = apiClient
    }

    public func transcribe(audioFileURL: URL) async throws -> TranscriptionResult {
        let token = try loadToken()
        let audioData = try Data(contentsOf: audioFileURL)

        var form = MultipartFormData()
        form.append(data: audioData, name: "file", fileName: audioFileURL.lastPathComponent, mimeType: "audio/wav")
        form.appendString(GroqConstants.model, name: "model")
        form.appendString("json", name: "response_format")

        let endpoint = GroqTranscriptionEndpoint(form: form, token: token)

        do {
            let response: GroqResponse = try await apiClient.send(endpoint)
            return TranscriptionResult(text: response.text)
        } catch let error as NetworkError {
            throw TranscriptionError(from: error)
        }
    }

    // MARK: - Credential loading

    /// Tries Keychain first; falls back to Info.plist for first-launch bootstrap.
    private func loadToken() throws -> String {
        if let token = try? KeychainTokenStore.load(key: GroqConstants.keychainKey), !token.isEmpty {
            return token
        }
        guard
            let plistToken = Bundle.main.infoDictionary?["GROQ_API_KEY"] as? String,
            !plistToken.isEmpty
        else {
            throw NetworkError.missingCredentials
        }
        try? KeychainTokenStore.save(token: plistToken, key: GroqConstants.keychainKey)
        return plistToken
    }
}

// MARK: - Private endpoint

private struct GroqTranscriptionEndpoint: Endpoint {
    let form: MultipartFormData
    let token: String

    var path: String       { "/openai/v1/audio/transcriptions" }
    var method: HTTPMethod { .post }
    var body: RequestBody  { .multipart(form) }
    var headers: [String: String] {
        [
            "Authorization": "Bearer \(token)",
            "Connection": "close"
        ]
    }
}

// MARK: - Private response model

private struct GroqResponse: Decodable {
    let text: String
}

// MARK: - Centralized NetworkError → TranscriptionError mapping

private extension TranscriptionError {
    init(from networkError: NetworkError) {
        switch networkError {
        case .rateLimited(let retryAfter):
            self = .rateLimited(retryAfter: retryAfter)
        case .httpError(let code, _):
            self = .httpError(statusCode: code)
        case .decodingFailed:
            self = .decodingFailed
        case .invalidURL, .missingCredentials:
            self = .httpError(statusCode: 0)
        }
    }
}
