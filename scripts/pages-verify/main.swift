import Foundation
final class Generation: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 1
    func get() -> Int64 { lock.withLock { value } }
    func advance() { lock.withLock { value += 1 } }
}
actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

// Models a provider callback that can still arrive after its request was
// cancelled. Tests decide when to release each request instead of racing sleeps.
private actor PendingPage {
    private var started = false
    private var cancelled = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var cancellation: CheckedContinuation<Void, Never>?
    private var response: CheckedContinuation<Void, Never>?

    func load(_ value: String) async -> String {
        started = true
        arrival?.resume()
        arrival = nil
        await withTaskCancellationHandler {
            if !released {
                await withCheckedContinuation { response = $0 }
            }
        } onCancel: {
            Task { await self.noteCancellation() }
        }
        return value
    }

    func waitForStart() async {
        if !started { await withCheckedContinuation { arrival = $0 } }
    }

    func waitForCancellation() async {
        if !cancelled { await withCheckedContinuation { cancellation = $0 } }
    }

    func release() {
        released = true
        response?.resume()
        response = nil
    }

    private func noteCancellation() {
        cancelled = true
        cancellation?.resume()
        cancellation = nil
    }
}

private final class ReaderArrival: @unchecked Sendable {
    private let lock = NSLock()
    private var arrived = false

    func report(generation: Int64) -> Int64 {
        lock.withLock { arrived = true }
        return generation
    }

    func wait() async {
        // The generation check is synchronous in the coordinator actor, so
        // its registration is ordered before any subsequent actor message.
        while !lock.withLock({ arrived }) {
            await Task.yield()
        }
    }
}

private func expectCancellation(_ reader: Task<String, Error>) async throws {
    do {
        _ = try await reader.value
        preconditionFailure("A cancelled reader accepted a page")
    } catch is CancellationError {}
}

private func verifyPartitionInvalidation() async throws {
    let repository = PageRequestCoordinator()
    let first = PageContext(identity: "account-a:channel", generation: 1, locale: "en", region: "US")
    let second = PageContext(identity: "account-b:channel", generation: 1, locale: "en", region: "US")
    let a = PendingPage(), b = PendingPage()
    let readerA = Task { try await repository.fetch("library", context: first, currentGeneration: { 1 }) { await a.load("old") } }
    let readerB = Task { try await repository.fetch("library", context: second, currentGeneration: { 1 }) { await b.load("other") } }
    await a.waitForStart()
    await b.waitForStart()
    await repository.invalidate(partition: first.partition)
    await a.release()
    await b.release()
    try await expectCancellation(readerA)
    let other = try await readerB.value
    precondition(other == "other", "A library mutation must leave another partition's reader intact")

    let pending = PendingPage()
    let reader = Task { try await repository.fetch("library", context: second, currentGeneration: { 1 }) { await pending.load("obsolete") } }
    await pending.waitForStart()
    await repository.invalidate()
    try await expectCancellation(reader) // Return before the cancelled callback.
    await pending.waitForCancellation()
    await pending.release()
    print("PASS scoped library mutation and global session invalidation")
}

private func verifyReaderCancellation() async throws {
    let repository = PageRequestCoordinator()
    let context = PageContext(identity: "account:channel", generation: 1, locale: "en", region: "US")
    let pending = PendingPage()
    let early = Task { try await repository.fetch("albums", context: context, currentGeneration: { 1 }) { await pending.load("shared") } }
    await pending.waitForStart()
    let arrival = ReaderArrival()
    let remaining = Task<String, Error> {
        try await repository.fetch("albums", context: context, currentGeneration: { arrival.report(generation: 1) }) { () -> String in
            preconditionFailure("The remaining reader should use the same request")
        }
    }
    await arrival.wait()
    early.cancel()
    try await expectCancellation(early) // Still blocked in the simulated provider.
    await pending.release()
    let result = try await remaining.value
    precondition(result == "shared")

    let obsolete = PendingPage()
    let abandoned = Task {
        try await repository.fetch("albums", context: context, currentGeneration: { 1 }) { await obsolete.load("obsolete") }
    }
    await obsolete.waitForStart()
    abandoned.cancel()
    try await expectCancellation(abandoned)
    await obsolete.waitForCancellation()

    let successor = PendingPage()
    let next = Task {
        try await repository.fetch("albums", context: context, currentGeneration: { 1 }) { await successor.load("replacement") }
    }
    await successor.waitForStart()
    await obsolete.release()
    let join = ReaderArrival()
    let companion = Task<String, Error> {
        try await repository.fetch("albums", context: context, currentGeneration: { join.report(generation: 1) }) { () -> String in
            preconditionFailure("An obsolete callback must not evict its replacement flight")
        }
    }
    await join.wait()
    await successor.release()
    let first = try await next.value
    let second = try await companion.value
    precondition(first == "replacement" && second == "replacement")
    print("PASS prompt reader cancellation, last-reader transfer cancellation and late callback isolation")
}

private func verifyForcedRefresh() async throws {
    let repository = PageRequestCoordinator()
    let context = PageContext(identity: "account:channel", generation: 1, locale: "en", region: "US")
    let pending = PendingPage(), refresh = PendingPage()
    let regular = Task { try await repository.fetch("detail", context: context, currentGeneration: { 1 }) { await pending.load("original") } }
    await pending.waitForStart()
    let forced = Task {
        try await repository.fetch("detail", context: context, force: true, currentGeneration: { 1 }) { await refresh.load("fresh") }
    }
    await refresh.waitForStart()
    await pending.waitForCancellation()
    await pending.release()
    let arrival = ReaderArrival()
    let secondRefresh = Task<String, Error> {
        try await repository.fetch("detail", context: context, force: true, currentGeneration: { arrival.report(generation: 1) }) { () -> String in
            preconditionFailure("Simultaneous forced refreshes should coalesce")
        }
    }
    await arrival.wait()
    let backgroundArrival = ReaderArrival()
    let background = Task<String, Error> {
        try await repository.fetch("detail", context: context, currentGeneration: { backgroundArrival.report(generation: 1) }) { () -> String in
            preconditionFailure("An ordinary reader should also share an active refresh")
        }
    }
    await backgroundArrival.wait()
    await refresh.release()
    let values = try await [regular.value, forced.value, secondRefresh.value, background.value]
    precondition(values == ["fresh", "fresh", "fresh", "fresh"])
    print("PASS explicit refresh supersedes an older read and delivers one fresh page to all readers")
}

@main struct Verify {
    static func main() async throws {
        let watchdog = Task {
            try await Task.sleep(for: .seconds(15))
            preconditionFailure("Page request verification stalled")
        }
        defer { watchdog.cancel() }

        let repository = PageRequestCoordinator()
        let gen = Generation()
        let context = PageContext(identity: "account:channel", generation: 1, locale: "en", region: "US")
        let requests = Counter()
        for _ in 0..<2 {
            let value: String = try await repository.fetch("home", context: context, currentGeneration: { gen.get() }) {
                await requests.increment(); return "fresh"
            }
            precondition(value == "fresh")
        }
        let count = await requests.value
        precondition(count == 2, "Completed pages must never be cached")
        let concurrent = Counter()
        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    try await repository.fetch("explore", context: context, currentGeneration: { gen.get() }) {
                        await concurrent.increment(); try await Task.sleep(for: .milliseconds(100)); return "feed"
                    }
                }
            }
            for try await result in group { precondition(result == "feed") }
        }
        let coalesced = await concurrent.value
        precondition(coalesced == 1, "Concurrent identical reads must coalesce")
        do {
            let _: String = try await repository.fetch("home", context: context, currentGeneration: { gen.get() }) {
                throw URLError(.notConnectedToInternet)
            }
            fatalError("Offline read returned retained data")
        } catch let error as URLError { precondition(error.code == .notConnectedToInternet) }
        do {
            let _: String = try await repository.fetch("obsolete", context: context, currentGeneration: { gen.get() }) {
                gen.advance(); return "obsolete"
            }
            fatalError("Old account response escaped")
        } catch is CancellationError {}
        let nextContext = PageContext(identity: context.identity, generation: gen.get(), locale: context.locale, region: context.region)
        do {
            let _: String = try await repository.fetch("obsolete error", context: nextContext, currentGeneration: { gen.get() }) {
                gen.advance()
                throw URLError(.userAuthenticationRequired)
            }
            fatalError("Expected the obsolete account's error to be discarded")
        } catch is CancellationError {}
        print("PASS fresh revisits, concurrent deduplication, offline errors, obsolete account rejection")
        try await verifyPartitionInvalidation()
        try await verifyReaderCancellation()
        try await verifyForcedRefresh()
    }
}
