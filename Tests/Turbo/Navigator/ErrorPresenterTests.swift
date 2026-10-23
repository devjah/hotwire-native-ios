@testable import HotwireNative
import SwiftUI
import UIKit
import XCTest

final class ErrorPresenterTests: XCTestCase {
    func test_presentingAgainReplacesTheErrorView() {
        let controller = UIViewController()

        controller.presentError(.load(.notPresent), retryHandler: nil)
        controller.presentError(.load(.notReady), retryHandler: nil)

        XCTAssertEqual(errorViews(in: controller), 1)
        XCTAssertEqual(controller.view.subviews.count, 1)
    }

    func test_removeErrorViewControllerRemovesTheErrorView() {
        let controller = UIViewController()
        controller.presentError(.load(.notPresent), retryHandler: nil)

        controller.removeErrorViewController()

        XCTAssertEqual(errorViews(in: controller), 0)
        XCTAssertTrue(controller.view.subviews.isEmpty)
    }

    private func errorViews(in controller: UIViewController) -> Int {
        controller.children.filter { $0 is UIHostingController<AnyView> }.count
    }
}
