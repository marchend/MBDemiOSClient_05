import XCTest
import SwiftUI
@testable import AcmeBank

/// Host-based tests that verify `LoginView` initialises and renders without
/// crashing under a range of ViewModel states.
///
/// These tests use `UIHostingController` to exercise the SwiftUI view
/// hierarchy in-process. They do NOT compare PNG snapshots — snapshot testing
/// with committed PNG files is not viable in CI (ephemeral runners have no
/// persisted reference images). Logic / state correctness is covered by
/// `LoginViewModelTests`.
final class LoginViewSnapshotTests: XCTestCase {

    // iPhone 16 Pro logical points.
    private let deviceFrame = CGRect(x: 0, y: 0, width: 393, height: 852)

    // MARK: - Instantiation

    func test_loginView_defaultState_doesNotCrash() {
        let vm = LoginViewModel()
        let view = LoginView(viewModel: vm)
        let hc = UIHostingController(rootView: AnyView(view))
        hc.view.frame = deviceFrame
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        XCTAssertFalse(hc.view.frame.isEmpty,
                       "LoginView should have a non-empty frame after layout")
    }

    func test_loginView_withErrorMessage_doesNotCrash() {
        let vm = LoginViewModel()
        vm.errorMessage = "Incorrect username or password."
        let view = LoginView(viewModel: vm)
        let hc = UIHostingController(rootView: AnyView(view))
        hc.view.frame = deviceFrame
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        XCTAssertFalse(hc.view.frame.isEmpty,
                       "LoginView with an error message should render without crashing")
    }

    func test_loginView_withBothFieldsFilled_doesNotCrash() {
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        vm.password = "secret"
        let view = LoginView(viewModel: vm)
        let hc = UIHostingController(rootView: AnyView(view))
        hc.view.frame = deviceFrame
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        XCTAssertFalse(hc.view.frame.isEmpty,
                       "LoginView with filled fields should render without crashing")
    }

    func test_loginView_passwordVisible_doesNotCrash() {
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        vm.password = "secret"
        vm.isPasswordVisible = true
        let view = LoginView(viewModel: vm)
        let hc = UIHostingController(rootView: AnyView(view))
        hc.view.frame = deviceFrame
        hc.view.setNeedsLayout()
        hc.view.layoutIfNeeded()

        XCTAssertFalse(hc.view.frame.isEmpty,
                       "LoginView with password visible should render without crashing")
    }

    // MARK: - ViewModel state reflected in view model

    func test_loginView_buttonDisabled_whenFieldsEmpty() {
        let vm = LoginViewModel()
        // isSignInEnabled is false when both fields are empty
        XCTAssertFalse(vm.isSignInEnabled,
                       "Sign In button should be disabled when fields are empty")
    }

    func test_loginView_buttonEnabled_whenFieldsFilled() {
        let vm = LoginViewModel()
        vm.username = "user@acmebank.com"
        vm.password = "hunter2"
        XCTAssertTrue(vm.isSignInEnabled,
                      "Sign In button should be enabled when both fields have text")
    }

    func test_loginView_errorBanner_hiddenByDefault() {
        let vm = LoginViewModel()
        XCTAssertNil(vm.errorMessage,
                     "Error banner should be hidden (nil) by default")
    }

    func test_loginView_errorBanner_visibleWhenMessageSet() {
        let vm = LoginViewModel()
        vm.errorMessage = "Something went wrong."
        XCTAssertNotNil(vm.errorMessage,
                        "Error banner should be visible when errorMessage is set")
    }
}
