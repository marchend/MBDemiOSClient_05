import XCTest
@testable import AcmeBank

/// Unit tests for `HomeViewModel` — the state machine, the 401 →
/// `onSessionExpired` routing, and the retry-after-failure path.
///
/// All tests are `@MainActor` because `HomeViewModel` is itself
/// `@MainActor`-isolated.
@MainActor
final class HomeViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSession() -> UserSession {
        return UserSession(
            userId: "00uabc123",
            displayName: "Marc Henderson",
            email: "marc@acmebank.com",
            accessToken: "test-access-token",
            authTimestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Device"
        )
    }

    /// Test-only counter wrapped in a class so multiple closures can
    /// mutate the same box without escaping-capture warnings.
    private final class CallCounter {
        var count: Int = 0
        func bump() { count += 1 }
    }

    // MARK: - Happy path

    /// Happy path: a healthy stub repository ends the load in
    /// `.loaded` carrying the fixture dashboard.
    func test_load_happyPath_endsInLoaded() async {
        let counter = CallCounter()
        let repo = StubHomeRepository(behaviour: .success(StubHomeRepository.bankuserOne))
        let vm = HomeViewModel(
            session: makeSession(),
            repository: repo,
            onSessionExpired: { counter.bump() }
        )

        await vm.load()

        XCTAssertEqual(vm.state, .loaded(StubHomeRepository.bankuserOne))
        XCTAssertEqual(counter.count, 0,
                       "Happy path must NOT invoke onSessionExpired")
    }

    // MARK: - Loading transition

    /// Transient `.loading` state is observable while a fetch is in
    /// flight. Uses a controllable repository that suspends on a
    /// continuation so the test can assert state == `.loading` BEFORE
    /// resuming the fetch.
    func test_load_publishesLoadingBeforeCompletion() async {
        let repo = ControllableHomeRepository()
        let vm = HomeViewModel(
            session: makeSession(),
            repository: repo,
            onSessionExpired: { XCTFail("happy path must not session-expire") }
        )

        XCTAssertEqual(vm.state, .idle, "precondition: initial state is .idle")

        // Kick off the load but do NOT await it yet — the controllable
        // repo will suspend until we call `repo.finish(with:)`.
        let task = Task { await vm.load() }

        // Wait until the repository's `fetchHome()` is actually
        // suspended on its continuation. This is the only safe way to
        // observe `.loading` deterministically: a synchronous-return
        // stub would race the assertion below.
        await repo.waitUntilFetching()

        XCTAssertEqual(vm.state, .loading,
                       "While the repository is mid-fetch the VM must publish .loading")

        // Let the repository finish; the load task then resumes and
        // publishes `.loaded`.
        repo.finish(with: .success(StubHomeRepository.bankuserOne))
        await task.value

        XCTAssertEqual(vm.state, .loaded(StubHomeRepository.bankuserOne))
    }

    // MARK: - 401 routing

    /// On 401 the VM invokes `onSessionExpired` exactly once and the
    /// state never becomes `.loaded`. The state ends at `.idle` (not
    /// `.loading`, so a spinner doesn't linger during the route
    /// transition to Login).
    func test_load_unauthorized_invokesOnSessionExpiredOnce_andStateIsNotLoaded() async {
        let counter = CallCounter()
        let repo = StubHomeRepository(behaviour: .failure(.unauthorized))
        let vm = HomeViewModel(
            session: makeSession(),
            repository: repo,
            onSessionExpired: { counter.bump() }
        )

        await vm.load()

        XCTAssertEqual(counter.count, 1,
                       "401 must invoke onSessionExpired exactly once")
        if case .loaded = vm.state {
            XCTFail("401 must NOT publish .loaded; got \(vm.state)")
        }
        XCTAssertEqual(vm.state, .idle,
                       "After 401 the VM should revert to .idle so no stale spinner lingers")
    }

    // MARK: - 5xx then retry

    /// A 5xx ends in `.error`. A subsequent `retry()` with a healthy
    /// repository ends in `.loaded`. Demonstrates that the VM doesn't
    /// latch onto a previous failure.
    func test_load_serverError_thenRetryWithHealthyRepo_endsInLoaded() async {
        let counter = CallCounter()
        let repo = SwappableHomeRepository(initial: .failure(.serverError(status: 503)))
        let vm = HomeViewModel(
            session: makeSession(),
            repository: repo,
            onSessionExpired: { counter.bump() }
        )

        await vm.load()

        guard case .error = vm.state else {
            return XCTFail("5xx must publish .error; got \(vm.state)")
        }

        // Heal the dependency and retry.
        repo.behaviour = .success(StubHomeRepository.bankuserOne)
        await vm.retry()

        XCTAssertEqual(vm.state, .loaded(StubHomeRepository.bankuserOne),
                       "After retry against a healthy repo the VM must end in .loaded")
        XCTAssertEqual(counter.count, 0,
                       "5xx must NOT invoke onSessionExpired")
    }

    // MARK: - Network error message (sanity)

    /// `.network` maps to a user-visible message (not an empty string)
    /// so the UI always has something to render on the error banner.
    func test_load_networkError_publishesNonEmptyErrorMessage() async {
        let repo = StubHomeRepository(behaviour: .failure(.network))
        let vm = HomeViewModel(
            session: makeSession(),
            repository: repo,
            onSessionExpired: { XCTFail("network error must not session-expire") }
        )

        await vm.load()

        guard case let .error(message) = vm.state else {
            return XCTFail(".network must publish .error; got \(vm.state)")
        }
        XCTAssertFalse(message.isEmpty,
                       "Error message must be non-empty so the banner has copy to render")
    }

    // MARK: - Cancellation

    /// Cancelling an in-flight `load()` must NOT overwrite `state`
    /// with `.error`. The VM's `catch is CancellationError { return }`
    /// branch exists precisely so the user doesn't see a spurious
    /// error banner flash when the view disappears mid-fetch.
    ///
    /// Mechanics: a `ControllableHomeRepository` configured with
    /// `cancellationThrows: true` wires a `withTaskCancellationHandler`
    /// around its continuation, so that when the parent task is
    /// cancelled the suspended `fetchHome()` re-throws
    /// `CancellationError()` — mirroring what `BFFHomeRepository` does
    /// in production when a `URLSession` data task is cancelled. The
    /// VM should observe that, hit the `catch is CancellationError`
    /// branch, and leave `state` at `.loading`. A regression that
    /// replaced the silent `return` with `state = .error(...)` would
    /// flip this test red.
    func test_load_cancellation_leavesStateUnchanged() async {
        let repo = ControllableHomeRepository(cancellationThrows: true)
        let vm = HomeViewModel(
            session: makeSession(),
            repository: repo,
            onSessionExpired: { XCTFail("cancellation must not session-expire") }
        )

        let task = Task { await vm.load() }

        // Wait for the VM to publish `.loading` and the repo to be
        // parked on its continuation.
        await repo.waitUntilFetching()
        XCTAssertEqual(vm.state, .loading,
                       "precondition: VM should be in .loading before we cancel")

        // Cancel — the repository's cancellation handler throws
        // CancellationError into the awaiting VM, which should hit
        // the silent-return branch in `load()`.
        task.cancel()
        await task.value

        XCTAssertEqual(vm.state, .loading,
                       "Cancelled load must not overwrite state — the silent CancellationError branch should fire")
    }
}

// MARK: - Test doubles

/// Mutable-behaviour repository for the retry-after-failure scenario.
/// Same shape as `StubHomeRepository` but its `behaviour` is `var` so
/// the test can swap from `.failure(...)` to `.success(...)` between
/// calls without constructing a new VM. Not `@MainActor`-isolated so
/// it can satisfy the non-isolated `HomeRepositoryProtocol` requirement
/// the same way `StubHomeRepository` does.
///
/// ### Thread-safety
///
/// `behaviour` is guarded by an `NSLock` so concurrent reads/writes
/// from a future test that fires two overlapping `Task { await
/// vm.load() }` calls don't race. The previous implementation relied
/// on the soft invariant "the test only mutates `behaviour` between
/// awaits" and opted out of the Sendable checker with
/// `@unchecked Sendable` and no synchronisation — the compiler can't
/// enforce that invariant, so any future concurrent-call test would
/// have silently exhibited a data race. Matching the discipline of
/// `ControllableHomeRepository` below removes the foot-gun.
private final class SwappableHomeRepository: HomeRepositoryProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var _behaviour: StubHomeRepository.Behaviour

    var behaviour: StubHomeRepository.Behaviour {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _behaviour
        }
        set {
            lock.lock()
            _behaviour = newValue
            lock.unlock()
        }
    }

    init(initial: StubHomeRepository.Behaviour) {
        self._behaviour = initial
    }

    func fetchHome() async throws -> HomeDashboard {
        switch behaviour {
        case .success(let dashboard):
            return dashboard
        case .failure(let error):
            throw error
        }
    }
}

/// Repository that suspends on a continuation until the test calls
/// `finish(with:)`. Lets the test observe the `.loading` state
/// deterministically (a `StubHomeRepository` returns instantly, so
/// there's no observable suspension window).
///
/// When constructed with `cancellationThrows: true`, the suspended
/// `fetchHome()` is wrapped in `withTaskCancellationHandler` so that
/// cancelling the awaiting task resumes the continuation with
/// `CancellationError()` — used by
/// `test_load_cancellation_leavesStateUnchanged`.
private final class ControllableHomeRepository: HomeRepositoryProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<HomeDashboard, Error>?
    private var pendingResult: Result<HomeDashboard, Error>?
    private var fetchingWaiters: [CheckedContinuation<Void, Never>] = []
    private var isFetching: Bool = false
    private let cancellationThrows: Bool

    init(cancellationThrows: Bool = false) {
        self.cancellationThrows = cancellationThrows
    }

    func fetchHome() async throws -> HomeDashboard {
        if cancellationThrows {
            return try await withTaskCancellationHandler {
                try await suspendForResult()
            } onCancel: {
                // Resume any in-flight continuation with
                // CancellationError so the awaiting task observes a
                // genuine cancellation throw (mirrors what URLSession
                // does when a data task is cancelled).
                self.cancelInFlight()
            }
        } else {
            return try await suspendForResult()
        }
    }

    private func suspendForResult() async throws -> HomeDashboard {
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            // If the test already scheduled a result before fetchHome
            // was called, deliver it immediately.
            if let pending = pendingResult {
                pendingResult = nil
                lock.unlock()
                cont.resume(with: pending)
                return
            }
            continuation = cont
            isFetching = true
            let waiters = fetchingWaiters
            fetchingWaiters = []
            lock.unlock()
            // Notify anyone who was waiting for fetchHome() to be
            // suspended on its continuation.
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    private func cancelInFlight() {
        lock.lock()
        if let cont = continuation {
            continuation = nil
            isFetching = false
            lock.unlock()
            cont.resume(throwing: CancellationError())
        } else {
            lock.unlock()
        }
    }

    /// Resume the suspended `fetchHome()` with the given outcome.
    func finish(with result: StubHomeRepository.Behaviour) {
        let mapped: Result<HomeDashboard, Error>
        switch result {
        case .success(let dashboard): mapped = .success(dashboard)
        case .failure(let error):     mapped = .failure(error)
        }

        lock.lock()
        if let cont = continuation {
            continuation = nil
            isFetching = false
            lock.unlock()
            cont.resume(with: mapped)
        } else {
            // fetchHome() hasn't been called yet — stash the result.
            pendingResult = mapped
            lock.unlock()
        }
    }

    /// Suspend until `fetchHome()` has been entered AND is parked on
    /// its continuation. Returns immediately if that has already
    /// happened.
    func waitUntilFetching() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isFetching {
                lock.unlock()
                cont.resume()
                return
            }
            fetchingWaiters.append(cont)
            lock.unlock()
        }
    }
}
