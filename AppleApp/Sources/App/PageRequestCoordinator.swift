import Foundation
import CryptoKit

/// Request identity contains no credentials.
struct PageContext: Sendable, Equatable {
    let identity: String
    let generation: Int64
    let locale: String
    let region: String

    var partition: String {
        PageRequestCoordinator.digest([identity, locale, region].joined(separator: "\u{0}"))
    }
}

/// Shares only requests currently running. Completed page data is never retained.
actor PageRequestCoordinator {
    static let shared = PageRequestCoordinator()
    private typealias PageResult = Result<any Sendable, Error>
    private typealias Reader = CheckedContinuation<PageResult, Never>

    private struct RequestKey: Hashable {
        let partition: String
        let generation: Int64
        let name: String
        let responseType: ObjectIdentifier
    }

    private struct Flight {
        let id: UUID
        let forced: Bool
        let task: Task<Void, Never>
        var readers: [UUID: Reader]
    }

    private var flights: [RequestKey: Flight] = [:]
    private var revision: UInt64 = 0
    private var partitionRevisions: [String: UInt64] = [:]

    nonisolated static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func fetch<T: Sendable>(_ name: String, context: PageContext, force: Bool = false,
               currentGeneration: @escaping @Sendable () -> Int64,
               network: @escaping @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        guard currentGeneration() == context.generation else { throw CancellationError() }
        let key = RequestKey(partition: context.partition, generation: context.generation, name: name,
                             responseType: ObjectIdentifier(T.self))
        let version = revision
        let partitionVersion = partitionRevisions[key.partition, default: 0]
        let reader = UUID()
        let response: PageResult = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .failure(CancellationError()))
                    return
                }
                register(continuation, reader: reader, key: key, force: force, network: network)
            }
        } onCancel: {
            Task { await self.cancelReader(reader, key: key) }
        }
        try Task.checkCancellation()
        guard currentGeneration() == context.generation, version == revision,
              partitionVersion == partitionRevisions[key.partition, default: 0] else { throw CancellationError() }
        guard let value = try response.get() as? T else { throw URLError(.cannotDecodeContentData) }
        return value
    }

    private func register<T: Sendable>(_ continuation: Reader, reader: UUID,
                                      key: RequestKey, force: Bool,
                                      network: @escaping @Sendable () async throws -> T) {
        let previous = flights[key]
        if let previous, !force || previous.forced {
            flights[key]?.readers[reader] = continuation
            return
        }

        // Upgrade an ordinary in-flight read to the explicit refresh. All of
        // its subscribers receive the same fresh response, even if the old
        // callback arrives after a view has requested the refresh.
        previous?.task.cancel()
        var readers = previous?.readers ?? [:]
        readers[reader] = continuation
        let id = UUID()
        let task = Task { [weak self] in
            let response: PageResult
            do { response = .success(try await network()) }
            catch { response = .failure(error) }
            await self?.complete(response, id: id, key: key)
        }
        flights[key] = Flight(id: id, forced: force, task: task, readers: readers)
    }

    private func complete(_ response: PageResult, id: UUID, key: RequestKey) {
        // A callback-based provider can finish after cancellation and after
        // a replacement flight, so only its own flight may use the response.
        guard flights[key]?.id == id, let flight = flights.removeValue(forKey: key) else { return }
        for reader in flight.readers.values { reader.resume(returning: response) }
    }

    private func cancelReader(_ reader: UUID, key: RequestKey) {
        guard let continuation = flights[key]?.readers.removeValue(forKey: reader) else { return }
        if let flight = flights[key], flight.readers.isEmpty {
            flights.removeValue(forKey: key)
            flight.task.cancel()
        }
        continuation.resume(returning: .failure(CancellationError()))
    }

    func invalidate(partition: String? = nil) {
        let keys: [RequestKey]
        if let partition {
            partitionRevisions[partition, default: 0] &+= 1
            keys = flights.keys.filter { $0.partition == partition }
        } else {
            revision &+= 1
            partitionRevisions.removeAll()
            keys = Array(flights.keys)
        }
        for key in keys {
            guard let flight = flights.removeValue(forKey: key) else { continue }
            flight.task.cancel()
            for reader in flight.readers.values { reader.resume(returning: .failure(CancellationError())) }
        }
    }
    /// One-time removal of the retired page cache, outside the main actor.
    func removeLegacyCache() {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BitChord/pages-v1", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }
}
