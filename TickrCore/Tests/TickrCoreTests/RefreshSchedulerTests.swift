import Foundation
import XCTest
@testable import TickrCore

final class RefreshSchedulerTests: XCTestCase {
    func testRequestSpacingHonorsIntervalAndBudget() async throws {
        let provider = MockQuoteProvider()
        let scheduler = RefreshScheduler(
            symbols: ["AAPL", "MSFT", "NVDA"],
            provider: provider,
            configuration: RefreshSchedulerConfiguration(interval: 15, requestsPerMinute: 60),
            clock: ManualRefreshSchedulerClock()
        )

        XCTAssertEqual(scheduler.requestSpacing, 5)

        let budgetLimitedScheduler = RefreshScheduler(
            symbols: ["AAPL", "MSFT", "NVDA"],
            provider: provider,
            configuration: RefreshSchedulerConfiguration(interval: 3, requestsPerMinute: 30),
            clock: ManualRefreshSchedulerClock()
        )

        XCTAssertEqual(budgetLimitedScheduler.requestSpacing, 2)
    }

    func testSchedulesQuotesAtInjectedClockTicks() async throws {
        let provider = MockQuoteProvider()
        let clock = ManualRefreshSchedulerClock()
        let scheduler = RefreshScheduler(
            symbols: ["aapl", "msft"],
            provider: provider,
            configuration: RefreshSchedulerConfiguration(interval: 10, requestsPerMinute: 60),
            clock: clock
        )
        var iterator = scheduler.start().makeAsyncIterator()

        let first = try await nextUpdate(from: &iterator)
        XCTAssertEqual(first.symbol, "AAPL")
        let firstRequests = await provider.requests()
        let firstSleeps = await clock.recordedSleeps()
        XCTAssertEqual(firstRequests, ["AAPL"])
        XCTAssertEqual(firstSleeps, [5])

        await clock.advance()
        let second = try await nextUpdate(from: &iterator)
        XCTAssertEqual(second.symbol, "MSFT")
        let secondRequests = await provider.requests()
        let secondSleeps = await clock.recordedSleeps()
        XCTAssertEqual(secondRequests, ["AAPL", "MSFT"])
        XCTAssertEqual(secondSleeps, [5, 5])

        scheduler.stop()
    }

    func testStopCancelsWork() async throws {
        let provider = MockQuoteProvider()
        let clock = ManualRefreshSchedulerClock()
        let scheduler = RefreshScheduler(symbols: ["AAPL", "MSFT"], provider: provider, clock: clock)
        var iterator = scheduler.start().makeAsyncIterator()

        _ = try await nextUpdate(from: &iterator)
        scheduler.stop()
        await clock.advance()

        let finished = await iterator.next()
        XCTAssertNil(finished)
        let requests = await provider.requests()
        XCTAssertEqual(requests, ["AAPL"])
    }

    func testProviderErrorsDoNotKillLoop() async throws {
        let provider = MockQuoteProvider(failingSymbols: ["AAPL"])
        let clock = ManualRefreshSchedulerClock()
        let scheduler = RefreshScheduler(
            symbols: ["AAPL", "MSFT"],
            provider: provider,
            configuration: RefreshSchedulerConfiguration(interval: 10, requestsPerMinute: 60),
            clock: clock
        )
        var iterator = scheduler.start().makeAsyncIterator()

        try await waitUntil { await provider.requests() == ["AAPL"] }
        await clock.advance()

        let update = try await nextUpdate(from: &iterator)
        XCTAssertEqual(update.symbol, "MSFT")
        let requests = await provider.requests()
        XCTAssertEqual(requests, ["AAPL", "MSFT"])

        scheduler.stop()
    }
}

private func nextUpdate(
    from iterator: inout AsyncStream<RefreshSchedulerUpdate>.Iterator,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> RefreshSchedulerUpdate {
    let update = await iterator.next()
    return try XCTUnwrap(update, file: file, line: line)
}

private func waitUntil(
    timeout: TimeInterval = 1,
    predicate: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await predicate() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for predicate")
}

private actor ManualRefreshSchedulerClock: RefreshSchedulerClock {
    private var sleeps: [TimeInterval] = []
    private var continuations: [CheckedContinuation<Void, Error>] = []

    func sleep(for seconds: TimeInterval) async throws {
        sleeps.append(seconds)
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func recordedSleeps() -> [TimeInterval] {
        sleeps
    }

    func advance() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor MockQuoteProvider: QuoteProvider {
    private var requestedSymbols: [String] = []
    private let failingSymbols: Set<String>

    init(failingSymbols: Set<String> = []) {
        self.failingSymbols = failingSymbols
    }

    func requests() -> [String] {
        requestedSymbols
    }

    func quote(for symbol: String) async throws -> Quote {
        requestedSymbols.append(symbol)
        if failingSymbols.contains(symbol) {
            throw MockQuoteProviderError.requestFailed
        }
        return Quote(
            symbol: symbol,
            currentPrice: 100,
            change: 1,
            percentChange: 1,
            high: 110,
            low: 90,
            open: 99,
            previousClose: 99,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private enum MockQuoteProviderError: Error {
    case requestFailed
}
