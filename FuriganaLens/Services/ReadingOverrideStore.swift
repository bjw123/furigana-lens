import Foundation

/// User-editable reading overrides loaded from bundle; persisted overrides saved in UserDefaults.
final class ReadingOverrideStore {
    static let shared = ReadingOverrideStore()

    private var overrides: [String: String] = [:]
    private let userDefaultsKey = "readingOverrides"

    private init() {
        loadBundle()
        loadUser()
    }

    func reading(for surface: String) -> String? {
        overrides[surface]
    }

    func setReading(_ reading: String, for surface: String) {
        overrides[surface] = reading
        saveUser()
    }

    private func loadBundle() {
        guard let url = Bundle.main.url(forResource: "reading_overrides", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        overrides.merge(dict) { _, new in new }
    }

    private func loadUser() {
        guard let dict = UserDefaults.standard.dictionary(forKey: userDefaultsKey) as? [String: String] else {
            return
        }
        overrides.merge(dict) { _, new in new }
    }

    private func saveUser() {
        UserDefaults.standard.set(overrides, forKey: userDefaultsKey)
    }
}
