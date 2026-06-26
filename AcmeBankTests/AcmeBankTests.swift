import XCTest
@testable import AcmeBank

final class AcmeBankTests: XCTestCase {
    /// Bootstrap proof-of-life: test target compiles and links against the
    /// app module. Real behaviour tests belong in feature stories.
    /// Do NOT assert on view rendering — SwiftUI Text does not render as
    /// UILabel, so hierarchy traversal would always fail.
    func test_contentView_initializes() {
        _ = ContentView()
    }
}
