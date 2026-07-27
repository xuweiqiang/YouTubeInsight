import AppKit
import CryptoKit
import Foundation
import Network
import Security

struct YouTubeOAuthConfiguration: Equatable {
    static let clientIDKey = "youtubeOAuthClientID"
    static let clientSecretKey = "youtubeOAuthClientSecret"

    let clientID: String
    let clientSecret: String

    static var current: YouTubeOAuthConfiguration? {
        let defaults = UserDefaults.standard
        guard let clientID = defaults.string(forKey: clientIDKey)?.nilIfBlank else {
            return nil
        }
        return YouTubeOAuthConfiguration(
            clientID: clientID,
            clientSecret: defaults.string(forKey: clientSecretKey)?.nilIfBlank ?? ""
        )
    }

    static func imported(from data: Data) throws -> YouTubeOAuthConfiguration {
        struct CredentialFile: Decodable {
            struct Installed: Decodable {
                let clientID: String
                let clientSecret: String?

                enum CodingKeys: String, CodingKey {
                    case clientID = "client_id"
                    case clientSecret = "client_secret"
                }
            }

            let installed: Installed
        }

        do {
            let file = try JSONDecoder().decode(CredentialFile.self, from: data)
            guard let clientID = file.installed.clientID.nilIfBlank else {
                throw YouTubeOAuthError.invalidCredentialFile
            }
            return YouTubeOAuthConfiguration(
                clientID: clientID,
                clientSecret: file.installed.clientSecret?.nilIfBlank ?? ""
            )
        } catch let error as YouTubeOAuthError {
            throw error
        } catch {
            throw YouTubeOAuthError.invalidCredentialFile
        }
    }
}

enum YouTubeOAuthError: LocalizedError {
    case missingConfiguration
    case invalidCredentialFile
    case browserCouldNotOpen
    case callbackFailed(String)
    case stateMismatch
    case authorizationDenied(String)
    case tokenExchangeFailed(String)
    case authorizationRequired
    case keychain(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return L10n.string(
                "youtube.error.missingClientID",
                fallback: "Import a Google OAuth desktop credential JSON file or enter its client ID first."
            )
        case .invalidCredentialFile:
            return L10n.string(
                "youtube.error.invalidCredentialFile",
                fallback: "This is not a valid Google OAuth desktop credential JSON file."
            )
        case .browserCouldNotOpen:
            return L10n.string(
                "youtube.error.browser",
                fallback: "The system browser could not be opened."
            )
        case let .callbackFailed(details):
            return L10n.format(
                "youtube.error.callback",
                fallback: "YouTube authorization callback failed: %@",
                details
            )
        case .stateMismatch:
            return L10n.string(
                "youtube.error.stateMismatch",
                fallback: "The authorization response could not be verified. Please try again."
            )
        case let .authorizationDenied(details):
            return L10n.format(
                "youtube.error.denied",
                fallback: "YouTube authorization was not completed: %@",
                details
            )
        case let .tokenExchangeFailed(details):
            return L10n.format(
                "youtube.error.token",
                fallback: "Could not obtain YouTube access: %@",
                details
            )
        case .authorizationRequired:
            return L10n.string(
                "youtube.error.reconnect",
                fallback: "The YouTube authorization expired. Bind the account again."
            )
        case let .keychain(details):
            return L10n.format(
                "youtube.error.keychain",
                fallback: "Could not access the macOS Keychain: %@",
                details
            )
        }
    }
}

struct YouTubeOAuthToken: Codable, Equatable {
    let clientID: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

final class YouTubeTokenStore: @unchecked Sendable {
    private let service = "com.local.YouTubeInsight.YouTubeOAuth"
    private let account = "primary"

    func load() throws -> YouTubeOAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw YouTubeOAuthError.keychain(Self.message(for: status))
        }
        do {
            return try JSONDecoder().decode(YouTubeOAuthToken.self, from: data)
        } catch {
            throw YouTubeOAuthError.keychain(error.localizedDescription)
        }
    }

    func save(_ token: YouTubeOAuthToken) throws {
        let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insert = query
            attributes.forEach { insert[$0.key] = $0.value }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw YouTubeOAuthError.keychain(Self.message(for: insertStatus))
            }
        } else if updateStatus != errSecSuccess {
            throw YouTubeOAuthError.keychain(Self.message(for: updateStatus))
        }
    }

    func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw YouTubeOAuthError.keychain(Self.message(for: status))
        }
    }

    private static func message(for status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    }
}

actor YouTubeOAuthManager {
    private let tokenStore: YouTubeTokenStore
    private let session: URLSession

    init(
        tokenStore: YouTubeTokenStore = YouTubeTokenStore(),
        session: URLSession = .shared
    ) {
        self.tokenStore = tokenStore
        self.session = session
    }

    func hasStoredAuthorization(for configuration: YouTubeOAuthConfiguration) -> Bool {
        guard let token = try? tokenStore.load() else {
            return false
        }
        return token.clientID == configuration.clientID
            && !token.refreshToken.isEmpty
    }

    func authorize(configuration: YouTubeOAuthConfiguration) async throws {
        let server = try OAuthLoopbackServer()
        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)"
        let verifier = Self.randomURLSafeString(byteCount: 64)
        let challenge = Self.codeChallenge(for: verifier)
        let state = Self.randomURLSafeString(byteCount: 32)

        var components = URLComponents(
            string: "https://accounts.google.com/o/oauth2/v2/auth"
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(
                name: "scope",
                value: "https://www.googleapis.com/auth/youtube.readonly"
            ),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        guard let authorizationURL = components.url else {
            throw YouTubeOAuthError.callbackFailed("Invalid authorization URL")
        }

        let opened = await MainActor.run {
            NSWorkspace.shared.open(authorizationURL)
        }
        guard opened else {
            server.cancel()
            throw YouTubeOAuthError.browserCouldNotOpen
        }

        let callbackURL = try await server.waitForCallback()
        let queryItems = URLComponents(
            url: callbackURL,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        let returnedState = queryItems.first(where: { $0.name == "state" })?.value
        guard returnedState == state else {
            throw YouTubeOAuthError.stateMismatch
        }
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            throw YouTubeOAuthError.authorizationDenied(error)
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw YouTubeOAuthError.callbackFailed("Missing authorization code")
        }

        let response = try await requestToken(
            fields: [
                "client_id": configuration.clientID,
                "client_secret": configuration.clientSecret,
                "code": code,
                "code_verifier": verifier,
                "grant_type": "authorization_code",
                "redirect_uri": redirectURI
            ]
        )
        guard let refreshToken = response.refreshToken?.nilIfBlank else {
            throw YouTubeOAuthError.tokenExchangeFailed("Missing refresh token")
        }
        try tokenStore.save(
            YouTubeOAuthToken(
                clientID: configuration.clientID,
                accessToken: response.accessToken,
                refreshToken: refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
            )
        )
    }

    func validAccessToken(
        configuration: YouTubeOAuthConfiguration,
        forceRefresh: Bool = false
    ) async throws -> String {
        guard let token = try tokenStore.load(),
              token.clientID == configuration.clientID else {
            throw YouTubeOAuthError.authorizationRequired
        }
        if !forceRefresh, token.expiresAt.timeIntervalSinceNow > 300 {
            return token.accessToken
        }

        let response: TokenResponse
        do {
            response = try await requestToken(
                fields: [
                    "client_id": configuration.clientID,
                    "client_secret": configuration.clientSecret,
                    "refresh_token": token.refreshToken,
                    "grant_type": "refresh_token"
                ]
            )
        } catch {
            try? tokenStore.clear()
            throw YouTubeOAuthError.authorizationRequired
        }
        let refreshed = YouTubeOAuthToken(
            clientID: configuration.clientID,
            accessToken: response.accessToken,
            refreshToken: response.refreshToken?.nilIfBlank ?? token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn))
        )
        try tokenStore.save(refreshed)
        return refreshed.accessToken
    }

    func revoke(configuration: YouTubeOAuthConfiguration?) async throws {
        guard let token = try tokenStore.load() else {
            return
        }
        var components = URLComponents(
            string: "https://oauth2.googleapis.com/revoke"
        )!
        components.queryItems = [
            URLQueryItem(
                name: "token",
                value: token.refreshToken.nilIfBlank ?? token.accessToken
            )
        ]
        if let url = components.url {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try? await session.data(for: request)
        }
        try tokenStore.clear()
    }

    private func requestToken(fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(
            url: URL(string: "https://oauth2.googleapis.com/token")!
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        var components = URLComponents()
        components.queryItems = fields
            .filter { !$0.value.isEmpty }
            .sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let details = Self.oauthErrorDetails(from: data)
            throw YouTubeOAuthError.tokenExchangeFailed(details)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw YouTubeOAuthError.tokenExchangeFailed(error.localizedDescription)
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
        }
    }

    private static func oauthErrorDetails(from data: Data) -> String {
        struct Response: Decodable {
            let error: String?
            let errorDescription: String?

            enum CodingKeys: String, CodingKey {
                case error
                case errorDescription = "error_description"
            }
        }
        if let response = try? JSONDecoder().decode(Response.self, from: data) {
            return response.errorDescription ?? response.error ?? "OAuth error"
        }
        return String(data: data, encoding: .utf8)?.nilIfBlank ?? "OAuth error"
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

private final class OAuthLoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "YouTubeInsight.OAuthLoopback")
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var pendingResult: Result<URL, Error>?
    private var didFinish = false

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: "127.0.0.1",
            port: .any
        )
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else {
                    return
                }
                switch state {
                case .ready:
                    guard let port = self.listener.port?.rawValue else {
                        continuation.resume(
                            throwing: YouTubeOAuthError.callbackFailed("Missing local port")
                        )
                        return
                    }
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: port)
                case let .failed(error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.receive(connection: connection, accumulated: Data())
            }
            listener.start(queue: queue)
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let result = self.pendingResult {
                    self.pendingResult = nil
                    continuation.resume(with: result)
                } else {
                    self.callbackContinuation = continuation
                }
            }
        }
    }

    func cancel() {
        queue.async {
            self.listener.cancel()
            self.finish(
                .failure(YouTubeOAuthError.callbackFailed("Authorization cancelled"))
            )
        }
    }

    private func receive(connection: NWConnection, accumulated: Data) {
        connection.start(queue: queue)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 32_768
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }
            var buffer = accumulated
            if let data {
                buffer.append(data)
            }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                self.handleRequest(buffer, connection: connection)
            } else if let error {
                self.finish(.failure(error))
                connection.cancel()
            } else {
                self.receive(connection: connection, accumulated: buffer)
            }
        }
    }

    private func handleRequest(_ data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8),
              let requestLine = request.components(separatedBy: "\r\n").first else {
            finish(.failure(YouTubeOAuthError.callbackFailed("Invalid local request")))
            connection.cancel()
            return
        }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2,
              let callbackURL = URL(string: "http://127.0.0.1\(parts[1])") else {
            finish(.failure(YouTubeOAuthError.callbackFailed("Invalid callback URL")))
            connection.cancel()
            return
        }

        let body = """
        <!doctype html><meta charset="utf-8">
        <title>YouTubeInsight</title>
        <style>body{font:16px -apple-system;padding:48px;text-align:center}</style>
        <h1>YouTube account connected</h1>
        <p>You can close this page and return to YouTubeInsight.</p>
        """
        let bodyData = Data(body.utf8)
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r
        """
        var response = Data(header.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
        finish(.success(callbackURL))
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !didFinish else {
            return
        }
        didFinish = true
        listener.cancel()
        if let continuation = callbackContinuation {
            callbackContinuation = nil
            continuation.resume(with: result)
        } else {
            pendingResult = result
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
