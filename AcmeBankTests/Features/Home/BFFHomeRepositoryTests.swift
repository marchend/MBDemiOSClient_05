import XCTest
@testable import AcmeBank

/// Behaviour tests for `BFFHomeRepository`. Uses a `URLProtocol`
/// stub to intercept the request at the `URLSession` boundary, so the
/// test exercises real request building + status-code mapping without
/// any network.
final class BFFHomeRepositoryTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeRepository(
        baseURL: URL = URL(string: "https://bff.example.com")!,
        token: String? = "test-access-token"
    ) -> BFFHomeRepository {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return BFFHomeRepository(
            baseURLProvider: { baseURL },
            accessTokenProvider: { token },
            session: session
        )
    }

    private static let happyPathBody: Data = """
    {
      "customer": {
        "id": "cust_x", "first_name": "X", "last_name": "Y",
        "email": "x@example.com", "phone_number": null
      },
      "accounts": [],
      "recent_transactions": []
    }
    """.data(using: .utf8)!

    // MARK: - Happy path

    func test_fetchHome_2xx_returnsDecodedDashboard() async throws {
        StubURLProtocol.handler = { _ in
            (Self.makeResponse(status: 200), Self.happyPathBody)
        }

        let dashboard = try await makeRepository().fetchHome()
        XCTAssertEqual(dashboard.customer.id, "cust_x")
        XCTAssertEqual(dashboard.accounts.count, 0)
    }

    // MARK: - Request shape

    func test_fetchHome_buildsGetRequest_atV1Home_withBearerToken_andNoCustomerIdInPath() async throws {
        var captured: URLRequest?
        StubURLProtocol.handler = { request in
            captured = request
            return (Self.makeResponse(status: 200), Self.happyPathBody)
        }

        _ = try await makeRepository(
            baseURL: URL(string: "https://bff.example.com")!,
            token: "tok-123"
        ).fetchHome()

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://bff.example.com/v1/home")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Authorization"),
            "Bearer tok-123"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")

        // Identity belongs in the token, NEVER in the URL. The path
        // must be the bare /v1/home and the query must be empty.
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/v1/home")
        XCTAssertNil(url.query)
        let lowercasedURL = url.absoluteString.lowercased()
        XCTAssertFalse(lowercasedURL.contains("customerid"),
                       "URL must not embed customerId: \(url.absoluteString)")
        XCTAssertFalse(lowercasedURL.contains("cif"),
                       "URL must not embed CIF: \(url.absoluteString)")
    }

    // MARK: - Error mapping

    func test_fetchHome_401_throwsUnauthorized() async {
        StubURLProtocol.handler = { _ in
            (Self.makeResponse(status: 401), Data())
        }

        do {
            _ = try await makeRepository().fetchHome()
            XCTFail("expected APIError.unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("expected APIError, got \(error)")
        }
    }

    func test_fetchHome_500_throwsServerError() async {
        StubURLProtocol.handler = { _ in
            (Self.makeResponse(status: 503), Data())
        }

        do {
            _ = try await makeRepository().fetchHome()
            XCTFail("expected APIError.serverError")
        } catch let error as APIError {
            XCTAssertEqual(error, .serverError(status: 503))
        } catch {
            XCTFail("expected APIError, got \(error)")
        }
    }

    func test_fetchHome_transportError_throwsNetwork() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            _ = try await makeRepository().fetchHome()
            XCTFail("expected APIError.network")
        } catch let error as APIError {
            XCTAssertEqual(error, .network)
        } catch {
            XCTFail("expected APIError, got \(error)")
        }
    }

    /// `URLError(.cancelled)` is what `URLSession.data(for:)` raises
    /// when the surrounding `Task` is cancelled. It must NOT collapse
    /// to `APIError.network` (which would show a "couldn't reach
    /// server" banner / trigger a retry); it must propagate as
    /// `CancellationError` so SwiftUI's `.task {}` modifier silently
    /// drops it.
    func test_fetchHome_taskCancellation_throwsCancellationError_notNetwork() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.cancelled)
        }

        do {
            _ = try await makeRepository().fetchHome()
            XCTFail("expected CancellationError")
        } catch is CancellationError {
            // success
        } catch let error as APIError {
            XCTFail("cancellation must not surface as APIError, got \(error)")
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func test_fetchHome_missingAccessToken_throwsUnauthorized_withoutHittingNetwork() async {
        StubURLProtocol.handler = { _ in
            XCTFail("network must not be touched when no token is available")
            return (Self.makeResponse(status: 200), Data())
        }

        do {
            _ = try await makeRepository(token: nil).fetchHome()
            XCTFail("expected APIError.unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("expected APIError, got \(error)")
        }
    }

    // MARK: - Fixtures

    private static func makeResponse(status: Int) -> HTTPURLResponse {
        return HTTPURLResponse(
            url: URL(string: "https://bff.example.com/v1/home")!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}

// MARK: - URLProtocol stub

/// Minimal `URLProtocol` that lets the test inject a (response, body)
/// pair OR a thrown error. State is global because `URLProtocol`
/// subclasses are constructed by `URLSession`; the test resets it
/// between cases via `reset()` in `tearDown`.
private final class StubURLProtocol: URLProtocol {

    /// Set by each test. Either returns a (response, body) tuple or
    /// throws to simulate a transport failure.
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
