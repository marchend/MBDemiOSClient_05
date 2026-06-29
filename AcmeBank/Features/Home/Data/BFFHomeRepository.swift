import Foundation

/// Production `HomeRepositoryProtocol` — calls `GET /v1/home` on the
/// configured BFF and decodes the contract payload.
///
/// **Identity is in the token, never in the URL.** The path is the bare
/// `/v1/home` — no `customerId` / `cif` / query string. The BFF derives
/// the user from the validated access token; embedding the customer id
/// client-side would be both a security smell (the client could ask for
/// somebody else's data and rely on the server to reject it) and a wire
/// duplication of what's already in the JWT.
public final class BFFHomeRepository: HomeRepositoryProtocol {

    /// Resolves the bearer access token at call time. A closure (vs a
    /// stored `UserSession`) so a future refresh-token rotation can
    /// transparently hand out the latest token without re-constructing
    /// the repository.
    public typealias AccessTokenProvider = () -> String?

    /// Lazily resolves the BFF base URL. A closure (vs a stored `URL`)
    /// so a missing `API_BASE_URL` surfaces as `APIError.notConfigured`
    /// at fetch time — i.e. the UI gets a clean error state instead of
    /// the app failing to construct the repository at composition root.
    public typealias BaseURLProvider = () throws -> URL

    private let baseURLProvider: BaseURLProvider
    private let accessTokenProvider: AccessTokenProvider
    private let session: URLSession

    public init(
        baseURLProvider: @escaping BaseURLProvider = { try AppConfig.apiBaseURL() },
        accessTokenProvider: @escaping AccessTokenProvider,
        session: URLSession = .shared
    ) {
        self.baseURLProvider = baseURLProvider
        self.accessTokenProvider = accessTokenProvider
        self.session = session
    }

    public func fetchHome() async throws -> HomeDashboard {
        let request = try makeRequest()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Swift structured concurrency surfaces `Task.cancel()` as
            // `URLError(.cancelled)` from `URLSession.data(for:)`. That
            // is NOT a network failure — the caller asked us to stop
            // (e.g. the user navigated away mid-fetch). Re-throw as a
            // `CancellationError` so the ViewModel's `.task {}` modifier
            // swallows it silently and we do NOT show a spurious
            // "couldn't reach server" banner or trigger a retry.
            throw CancellationError()
        } catch {
            // Everything else `URLSession` surfaces as `URLError`
            // (offline, DNS, TLS, timeout) collapses to `.network`
            // so the UI shows a single "couldn't reach" state.
            throw APIError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.decoding("response was not HTTP")
        }

        switch http.statusCode {
        case 200...299:
            return try decode(data)
        case 401:
            throw APIError.unauthorized
        case 500...599:
            throw APIError.serverError(status: http.statusCode)
        default:
            // 4xx other than 401 are programming errors at this seam
            // (we built the request) — surface as `serverError` so the
            // UI still degrades cleanly; engineers see the status in logs.
            throw APIError.serverError(status: http.statusCode)
        }
    }

    // MARK: - Internals

    /// Builds the `GET /v1/home` request. Internal for unit-test reach.
    func makeRequest() throws -> URLRequest {
        let baseURL: URL
        do {
            baseURL = try baseURLProvider()
        } catch let configError as AppConfig.ConfigError {
            switch configError {
            case .missing(let key):
                throw APIError.notConfigured("\(key) missing")
            case .invalidURL(let key, _):
                throw APIError.notConfigured("\(key) invalid")
            }
        } catch {
            throw APIError.notConfigured("base URL unavailable")
        }

        // `appendingPathComponent` preserves the host even if `baseURL`
        // already has a trailing slash; `/v1/home` is the only path.
        let url = baseURL.appendingPathComponent("v1/home")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token = accessTokenProvider(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            // No token → no point hitting the BFF; surface as
            // `.unauthorized` so the coordinator routes to login.
            throw APIError.unauthorized
        }

        return request
    }

    private func decode(_ data: Data) throws -> HomeDashboard {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(HomeDashboard.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
