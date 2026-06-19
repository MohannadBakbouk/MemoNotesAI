import Foundation

public struct MultipartFormData: Sendable {
    private let boundary: String
    private var parts: [Part] = []

    private struct Part: Sendable {
        let name: String
        let data: Data
        let fileName: String?
        let mimeType: String?
    }

    public init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
    }

    public mutating func append(
        data: Data,
        name: String,
        fileName: String? = nil,
        mimeType: String? = nil
    ) {
        parts.append(Part(name: name, data: data, fileName: fileName, mimeType: mimeType))
    }

    public mutating func appendString(_ value: String, name: String) {
        guard let data = value.data(using: .utf8) else { return }
        parts.append(Part(name: name, data: data, fileName: nil, mimeType: nil))
    }

    public func encode() -> (data: Data, contentType: String) {
        var body = Data()
        let crlf = "\r\n"
        let boundaryPrefix = "--\(boundary)\(crlf)"
        let finalBoundary = "--\(boundary)--\(crlf)"

        for part in parts {
            body.append(boundaryPrefix.utf8Data)
            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let fileName = part.fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            body.append((disposition + crlf).utf8Data)
            if let mimeType = part.mimeType {
                body.append("Content-Type: \(mimeType)\(crlf)".utf8Data)
            }
            body.append(crlf.utf8Data)
            body.append(part.data)
            body.append(crlf.utf8Data)
        }
        body.append(finalBoundary.utf8Data)
        return (body, "multipart/form-data; boundary=\(boundary)")
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
