import Foundation

enum SecretsManager {
    nonisolated static var geminiAPIKey: String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else {
            return nil
        }

        return normalizedKey(dictionary["GEMINI_API_KEY"] as? String)
    }

    nonisolated static var isGeminiConfigured: Bool {
        geminiAPIKey != nil
    }

    nonisolated static func normalizedKey(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$(") else {
            return nil
        }

        return value
    }
}
