import Foundation

public enum GroqConstants {
    public static let baseURL       = URL(string: "https://api.groq.com")!
    public static let model         = "whisper-large-v3-turbo"
    static let keychainKey          = "groq.api.token"
}
