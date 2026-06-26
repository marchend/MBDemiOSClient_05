import XCTest

/// Bootstrap UI smoke test: proves the XCUITest target compiles, links, and
/// can launch the host app. Full critical-flow tests (login, transfer,
/// sign-out) are added as feature stories land.
final class AcmeBankUITests: XCTestCase {
    func test_appLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.state == .runningForeground, "App should be running in the foreground")
    }
}
