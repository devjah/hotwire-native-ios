@testable import HotwireNative
import XCTest

final class HTTPCookieStorageExtensionTests: XCTestCase {
    private let url = URL(string: "https://example.com/page")!
    private let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "HTTPCookieStorageExtensionTests")

    override func setUp() {
        storage.cookies?.forEach(storage.deleteCookie)
    }

    func test_replaceCookies_removesCookiesNoLongerPresent() {
        storage.setCookies([cookie("session", "signed-in")], for: url, mainDocumentURL: url)

        storage.replaceCookies(for: url, with: [cookie("other", "value")])

        XCTAssertEqual(storage.cookies(for: url)?.map(\.name), ["other"])
    }

    func test_replaceCookies_updatesChangedValues() {
        storage.setCookies([cookie("session", "signed-in")], for: url, mainDocumentURL: url)

        storage.replaceCookies(for: url, with: [cookie("session", "signed-out")])

        XCTAssertEqual(storage.cookies(for: url)?.map(\.value), ["signed-out"])
    }

    func test_replaceCookies_leavesOtherDomainsAlone() {
        let otherURL = URL(string: "https://other.example.org")!
        storage.setCookies([cookie("other", "value", domain: "other.example.org")], for: otherURL, mainDocumentURL: otherURL)

        storage.replaceCookies(for: url, with: [])

        XCTAssertEqual(storage.cookies(for: otherURL)?.map(\.name), ["other"])
    }

    func test_replaceCookies_neverRemovesACookieStillPresent() {
        storage.setCookies([cookie("session", "0")], for: url, mainDocumentURL: url)
        let reader = ConcurrentCookieReader(storage: storage, url: url)

        reader.start()
        for value in 1...300 {
            storage.replaceCookies(for: url, with: [cookie("session", "\(value)"), cookie("csrf", "token")])
        }
        let result = reader.stop()

        XCTAssertGreaterThan(result.reads, 1)
        XCTAssertEqual(result.readsWithoutSession, 0)
    }

    private func cookie(_ name: String, _ value: String, domain: String = "example.com") -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/"])!
    }
}

/// Reads `storage` from another thread, as URLSession does for each request, and
/// counts the reads that found no session cookie for `url`.
private final class ConcurrentCookieReader {
    private let storage: HTTPCookieStorage
    private let url: URL
    private let lock = NSLock()
    private let firstRead = DispatchSemaphore(value: 0)
    private let finished = DispatchSemaphore(value: 0)
    private var running = true
    private var reads = 0
    private var readsWithoutSession = 0

    init(storage: HTTPCookieStorage, url: URL) {
        self.storage = storage
        self.url = url
    }

    /// Starts reading and returns once the first read is done.
    func start() {
        DispatchQueue.global().async { [self] in
            var signalled = false
            while isRunning {
                let hasSession = storage.cookies(for: url)?.contains { $0.name == "session" } ?? false
                record(hasSession: hasSession)
                if !signalled {
                    firstRead.signal()
                    signalled = true
                }
            }
            finished.signal()
        }
        firstRead.wait()
    }

    /// Stops reading and returns what the reads found.
    func stop() -> (reads: Int, readsWithoutSession: Int) {
        lock.lock()
        running = false
        lock.unlock()
        finished.wait()

        lock.lock()
        defer { lock.unlock() }
        return (reads, readsWithoutSession)
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private func record(hasSession: Bool) {
        lock.lock()
        defer { lock.unlock() }
        reads += 1
        if !hasSession { readsWithoutSession += 1 }
    }
}
