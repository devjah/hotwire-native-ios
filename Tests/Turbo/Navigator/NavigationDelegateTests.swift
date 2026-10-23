@testable import HotwireNative
import SafariServices
import XCTest

final class NavigationDelegateTests: XCTestCase {
    override func setUp() {
        delegate = TestNavigatorDelegate()
        navigator = Navigator(
            session: Session(webView: Hotwire.config.makeWebView()),
            modalSession: Session(webView: Hotwire.config.makeWebView()),
            configuration: .init(
                name: "",
                startLocation: URL(string: "https://example.com")!
            )
        )
    }

    override func tearDown() {
        navigator = nil
    }

    func test_handleProposalFrom_defaultsDefaultViewController() throws {
        let url = URL(string: "https://example.com/testing")!
        let proposal = VisitProposal(url: url, options: VisitOptions())

        let result = delegate.handle(proposal: proposal, from: navigator)
        XCTAssertEqual(result, .accept)
    }

    private var delegate: NavigatorDelegate!
    private var navigator: Navigator!

    private class TestNavigatorDelegate: NavigatorDelegate {}
}
