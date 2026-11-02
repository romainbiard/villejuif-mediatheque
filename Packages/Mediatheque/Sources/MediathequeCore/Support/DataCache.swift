// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// Read from the cache or force a reload (pull to refresh).
public enum CachePolicy: Sendable {
    case useCache
    case reload
}

/// A value from the cache or the portal. `refreshError` when the portal failed
/// and the value is the last one saved ("Mise à jour impossible" banner).
public struct Cached<Value: Sendable>: Sendable {
    public let value: Value
    public let refreshError: LoadError?

    public init(_ value: Value, refreshError: LoadError? = nil) {
        self.value = value
        self.refreshError = refreshError
    }
}

/// Cache for the portal's public data (agenda, opening hours, searches, availability).
/// Never account data here: it lives in the App Group snapshot, erased on sign-out.
///
/// - In memory, always; on disk (`Library/Caches`) when a `directory` is provided.
///   iOS may purge this folder at any time: the cache is only a speed-up.
/// - A fresh value (younger than `maxAge`) avoids the request; a stale value serves
///   as a fallback when the network or the site doesn't respond.
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

    /// The app's shared cache, on disk.
    public static let shared = DataCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "portail", directoryHint: .isDirectory)
    )

    /// Returns the cached value if it is fresh, otherwise calls `load` and stores the result.
    /// If `load` fails, a stale value is returned rather than the error.
    public func value<Value: Codable & Sendable>(
        for key: String,
        maxAge: TimeInterval,
        policy: CachePolicy = .useCache,
        persist: Bool = true,
        now: @Sendable () -> Date = { .now },
        load: @Sendable () async throws -> Value
    ) async throws -> Value {
        try await cached(for: key, maxAge: maxAge, policy: policy, persist: persist, now: now, load: load).value
    }

    /// Same as `value`, saying when the value is a stale one served because `load` failed.
    public func cached<Value: Codable & Sendable>(
        for key: String,
        maxAge: TimeInterval,
        policy: CachePolicy = .useCache,
        persist: Bool = true,
        now: @Sendable () -> Date = { .now },
        load: @Sendable () async throws -> Value
    ) async throws -> Cached<Value> {
        let cached: Entry<Value>? = entry(for: key, persist: persist)
        if policy == .useCache, let cached, now().timeIntervalSince(cached.savedAt) < maxAge {
            return Cached(cached.value)
        }
        do {
            let value = try await load()
            store(Entry(savedAt: now(), value: value), for: key, persist: persist)
            return Cached(value)
        } catch {
            if let cached { return Cached(cached.value, refreshError: LoadError(error)) }
            throw error
        }
    }

    // MARK: Storage

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

    private func store(_ entry: Entry<some Codable & Sendable>, for key: String, persist: Bool) {
        memory[key] = (entry.savedAt, entry.value)
        guard persist, let url = fileURL(for: key), let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fileURL(for key: String) -> URL? {
        let name = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return directory?.appending(path: "\(name).json")
    }
}
