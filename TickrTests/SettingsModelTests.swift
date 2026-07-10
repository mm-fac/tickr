import Foundation
import XCTest
import TickrCore
@testable import Tickr

@MainActor
final class SettingsModelTests: XCTestCase {

    // MARK: initial state

    func testInitReadsExistingKeyAndReportsLive() {
        let store = InMemoryAPIKeyStore(initial: "existing-key")
        let model = makeModel(store: store)

        XCTAssertEqual(model.keyDraft, "existing-key")
        XCTAssertTrue(model.isLive)
    }

    func testInitWithNoKeyReportsSampleData() {
        let model = makeModel(store: InMemoryAPIKeyStore())

        XCTAssertEqual(model.keyDraft, "")
        XCTAssertFalse(model.isLive)
    }

    // MARK: saving a key

    func testSavePersistsKeyAndGoesLive() async throws {
        let store = InMemoryAPIKeyStore()
        var changed = 0
        let model = makeModel(store: store)
        model.onProvidersChanged = { changed += 1 }

        model.keyDraft = "new-token"
        await model.save()

        XCTAssertEqual(try store.read(), "new-token")
        XCTAssertTrue(model.isLive)
        XCTAssertNil(model.saveError)
        XCTAssertEqual(changed, 1, "Saving should notify so on-screen data refreshes without a restart.")
    }

    func testSaveTrimsKeyBeforePersisting() async throws {
        let store = InMemoryAPIKeyStore()
        let model = makeModel(store: store)

        model.keyDraft = "   spaced-token   "
        await model.save()

        XCTAssertEqual(try store.read(), "spaced-token")
        XCTAssertTrue(model.isLive)
    }

    // MARK: clearing a key

    func testSaveBlankKeyClearsStoreAndReturnsToSampleData() async throws {
        let store = InMemoryAPIKeyStore(initial: "existing-key")
        var changed = 0
        let model = makeModel(store: store)
        model.onProvidersChanged = { changed += 1 }

        model.keyDraft = "   "
        await model.save()

        XCTAssertNil(try store.read())
        XCTAssertFalse(model.isLive)
        XCTAssertEqual(changed, 1)
    }

    // MARK: persistence failure

    func testSaveSurfacesErrorAndLeavesWiringUnchanged() async {
        let store = InMemoryAPIKeyStore()
        store.failWrites = true
        var changed = 0
        let model = makeModel(store: store)
        model.onProvidersChanged = { changed += 1 }

        model.keyDraft = "token"
        await model.save()

        XCTAssertNotNil(model.saveError)
        XCTAssertFalse(model.isLive, "A failed save must not flip the app to live wiring.")
        XCTAssertEqual(changed, 0, "A failed save should not trigger a provider refresh.")
    }

    // MARK: end-to-end wiring through the shared hub

    func testSavingRoutesTheSharedHubToLiveProvider() async throws {
        let store = InMemoryAPIKeyStore()
        let client = StubHTTPClient(json: finnhubQuoteJSON)
        let hub = ProviderHub(providers: SettingsModelTests.mockSet())
        let model = SettingsModel(store: store, hub: hub, mock: SettingsModelTests.mockSet(), httpClient: client)

        model.keyDraft = "token"
        await model.save()

        // The very same hub the view models hold now serves live Finnhub data — proof
        // the key took effect without rebuilding anything.
        let quote = try await hub.quote(for: "AAPL")
        XCTAssertEqual(quote.currentPrice, 261.74, accuracy: 0.0001)
        XCTAssertEqual(client.requests.count, 1)
    }

    // MARK: helpers

    private func makeModel(store: InMemoryAPIKeyStore) -> SettingsModel {
        SettingsModel(
            store: store,
            hub: ProviderHub(providers: Self.mockSet()),
            mock: Self.mockSet(),
            httpClient: StubHTTPClient(json: finnhubQuoteJSON)
        )
    }

    private static func mockSet() -> ProviderSet {
        ProviderSet(
            quote: MockQuoteProvider(),
            candle: PreviewCandleProvider(),
            search: MockSymbolSearchProvider(),
            isLive: false
        )
    }
}

/// In-memory ``APIKeyStore`` double so tests never touch the real Keychain (AGENTS.md).
final class InMemoryAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private var value: String?
    /// When true, ``write(_:)`` and ``delete()`` throw, simulating a Keychain denial.
    var failWrites = false

    init(initial: String? = nil) {
        self.value = initial
    }

    func read() throws -> String? { value }

    func write(_ key: String) throws {
        if failWrites { throw TestError.denied }
        value = key
    }

    func delete() throws {
        if failWrites { throw TestError.denied }
        value = nil
    }

    enum TestError: Error { case denied }
}

/// Canned ``HTTPClient`` so the wired ``FinnhubProvider`` never touches the network
/// (AGENTS.md). Records requests so tests can assert the hub actually routed through it.
final class StubHTTPClient: HTTPClient, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let data: Data
    private let statusCode: Int

    init(json: String, statusCode: Int = 200) {
        self.data = Data(json.utf8)
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url ?? URL(fileURLWithPath: "/")
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return (data, response)
    }
}

private let finnhubQuoteJSON = #"""
{ "c": 261.74, "d": 3.23, "dp": 1.2495, "h": 263.31, "l": 258.40, "o": 259.12, "pc": 258.51, "t": 1709596800 }
"""#
