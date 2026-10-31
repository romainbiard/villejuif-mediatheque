import Foundation

/// Lecture depuis le cache ou rechargement forcé (tirer pour rafraîchir).
public enum CachePolicy: Sendable {
    case useCache
    case reload
}

/// Cache des données publiques du portail (agenda, horaires, recherches, disponibilités).
/// Jamais de données du compte ici : elles vivent dans le snapshot de l'App Group, effacé à la déconnexion.
///
/// - En mémoire, toujours ; sur disque (`Library/Caches`) quand une `directory` est fournie.
///   iOS peut vider ce dossier à tout moment : le cache n'est qu'une accélération.
/// - Une valeur fraîche (moins de `maxAge`) évite la requête ; une valeur périmée sert
///   de repli quand le réseau ou le site ne répondent pas.
public actor DataCache {
    struct Entry<Value: Codable>: Codable {
        let savedAt: Date
        let value: Value
    }

    private let directory: URL?
    private var memory: [String: (savedAt: Date, value: any Sendable)] = [:]

    public init(directory: URL?) {
        self.directory = directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Cache partagé de l'app, sur disque.
    public static let shared = DataCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "portail", directoryHint: .isDirectory)
    )

    /// Renvoie la valeur en cache si elle est fraîche, sinon appelle `load` et la mémorise.
    /// Si `load` échoue, une valeur périmée est renvoyée plutôt que l'erreur.
    public func value<Value: Codable & Sendable>(
        for key: String,
        maxAge: TimeInterval,
        policy: CachePolicy = .useCache,
        persist: Bool = true,
        now: @Sendable () -> Date = { .now },
        load: @Sendable () async throws -> Value
    ) async throws -> Value {
        let cached: Entry<Value>? = entry(for: key, persist: persist)
        if policy == .useCache, let cached, now().timeIntervalSince(cached.savedAt) < maxAge {
            return cached.value
        }
        do {
            let value = try await load()
            store(Entry(savedAt: now(), value: value), for: key, persist: persist)
            return value
        } catch {
            if let cached { return cached.value }
            throw error
        }
    }

    public func removeAll() {
        memory.removeAll()
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Stockage

    private func entry<Value: Codable & Sendable>(for key: String, persist: Bool) -> Entry<Value>? {
        if let hit = memory[key], let value = hit.value as? Value {
            return Entry(savedAt: hit.savedAt, value: value)
        }
        guard persist, let url = fileURL(for: key),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry<Value>.self, from: data)
        else { return nil }
        memory[key] = (entry.savedAt, entry.value)
        return entry
    }

    private func store<Value: Codable & Sendable>(_ entry: Entry<Value>, for key: String, persist: Bool) {
        memory[key] = (entry.savedAt, entry.value)
        guard persist, let url = fileURL(for: key), let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fileURL(for key: String) -> URL? {
        let name = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return directory?.appending(path: "\(name).json")
    }
}
