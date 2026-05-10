import Foundation
import Observation

@MainActor
@Observable
public final class MainFlowModel {
    public enum State: Sendable {
        case idle
        case loadingCreds
        case needsLogin
        case signingIn(email: String)
        case refreshingQR
        case buildingPass
        case ready(token: QRToken, passData: Data?)
        case failed(message: String)
    }

    public var state: State = .idle {
        didSet { AppLog.flow.info("state → \(String(describing: self.state), privacy: .public)") }
    }

    public var isManualRefreshing: Bool = false
    public var refreshError: String?

    /// Tokens are issued for ~30 days; refresh fires this long before expiry.
    public var refreshLeadTime: TimeInterval = 5 * 60

    private let auth = Authenticator()
    private var refreshTask: Task<Void, Never>?

    public init() {}

    public func start() async {
        AppLog.flow.info("start()")
        state = .loadingCreds

        let storedCreds: KeychainStore.Credentials?
        do {
            storedCreds = try KeychainStore.loadCredentials()
        } catch {
            AppLog.flow.error("loadCredentials failed: \(String(describing: error), privacy: .public)")
            storedCreds = nil
        }
        guard let creds = storedCreds else {
            state = .needsLogin
            return
        }

        await ExpiryNotifier.requestProvisionalAuthorization()

        if let cached = loadValidCachedToken() {
            AppLog.flow.info("start: hydrating from cached token (expires \(cached.expiresAt.description, privacy: .public))")
            state = .ready(token: cached, passData: nil)
            scheduleExpiryRefresh(expiresAt: cached.expiresAt)
            await ExpiryNotifier.scheduleWarning(expiresAt: cached.expiresAt)
            await rebuildPassFromCacheInBackground(token: cached)
            return
        }

        state = .signingIn(email: creds.email)

        do {
            let jwt = try await auth.currentJWT()

            state = .refreshingQR
            let token = try await QRRefresher.refresh(jwt: jwt)
            persistCachedToken(token)

            state = .buildingPass
            let passData = buildPass(token: token, jwt: jwt)

            state = .ready(token: token, passData: passData)
            scheduleExpiryRefresh(expiresAt: token.expiresAt)
            await ExpiryNotifier.scheduleWarning(expiresAt: token.expiresAt)
        } catch let e as AuthError {
            AppLog.flow.error("AuthError: \(String(describing: e), privacy: .public)")
            state = .failed(message: Self.describe(authError: e))
        } catch let e as QRError {
            AppLog.flow.error("QRError: \(String(describing: e), privacy: .public)")
            state = .failed(message: Self.describe(qrError: e))
        } catch {
            AppLog.flow.error("Unknown error: \(String(describing: error), privacy: .public)")
            state = .failed(message: String(
                localized: "Unexpected error: \(String(describing: error))",
                bundle: .module
            ))
        }
    }

    public func handleLogin(email: String, password: String) async {
        AppLog.flow.info("handleLogin email=\(email, privacy: .private)")
        state = .signingIn(email: email)
        do {
            _ = try await auth.signIn(email: email, password: password)
            await start()
        } catch {
            AppLog.flow.error("handleLogin AuthError: \(String(describing: error), privacy: .public)")
            state = .failed(message: Self.describe(authError: error))
        }
    }

    public func signOut() async {
        AppLog.flow.info("signOut()")
        refreshTask?.cancel()
        refreshTask = nil
        ExpiryNotifier.cancelWarning()
        try? KeychainStore.clearAll()
        await auth.signOut()
        state = .needsLogin
    }

    public func cancelAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Re-arms the expiry timer on foreground. Refreshes immediately if the
    /// cached token already lapsed.
    public func resumeAutoRefresh() {
        guard case let .ready(token, _) = state else { return }
        if Date() >= token.expiresAt {
            Task { await self.silentRefresh(reason: "expired-on-resume") }
        } else {
            scheduleExpiryRefresh(expiresAt: token.expiresAt)
        }
    }

    public func manualRefresh() async {
        guard !isManualRefreshing else { return }
        AppLog.flow.info("manualRefresh()")
        isManualRefreshing = true
        defer { isManualRefreshing = false }

        do {
            try await refreshTokenAndPass(reason: "manual")
        } catch {
            AppLog.flow.error("manualRefresh failed: \(String(describing: error), privacy: .public)")
            refreshError = Self.describeRefresh(error: error)
        }
    }

    /// Failures are non-fatal — the existing QR stays visible until the next
    /// foreground entry retries.
    public func silentRefresh(reason: String = "scheduled") async {
        guard case .ready = state else { return }
        AppLog.flow.info("silentRefresh(\(reason, privacy: .public))")
        do {
            try await refreshTokenAndPass(reason: reason)
        } catch {
            AppLog.flow.error("silentRefresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Internals

    private func refreshTokenAndPass(reason: String) async throws {
        let jwt = try await auth.currentJWT()
        let token = try await QRRefresher.refresh(jwt: jwt)
        persistCachedToken(token)

        let passData = buildPass(token: token, jwt: jwt)
        state = .ready(token: token, passData: passData)

        if let data = passData {
            let replaced = await PassAdder.replaceIfPresent(passData: data)
            AppLog.flow.info("refresh(\(reason, privacy: .public)) wallet replaced=\(replaced, privacy: .public)")
        }

        scheduleExpiryRefresh(expiresAt: token.expiresAt)
        await ExpiryNotifier.scheduleWarning(expiresAt: token.expiresAt)
    }

    private func buildPass(token: QRToken, jwt: JWT) -> Data? {
        do {
            let signer = try PassSigner()
            return try PassBuilder(
                qrToken: token,
                serialNumber: jwt.sub
            ).build(signer: signer)
        } catch {
            AppLog.flow.error("Pass build failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func rebuildPassFromCacheInBackground(token: QRToken) async {
        do {
            let jwt = try await auth.currentJWT()
            let passData = buildPass(token: token, jwt: jwt)
            if case let .ready(currentToken, _) = state, currentToken.hex == token.hex {
                state = .ready(token: token, passData: passData)
            }
        } catch {
            AppLog.flow.error("cache rehydrate JWT failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func loadValidCachedToken() -> QRToken? {
        do {
            guard let cached = try KeychainStore.loadQRToken() else { return nil }
            guard cached.expiresAt > Date() else {
                AppLog.flow.info("cached QR token expired at \(cached.expiresAt.description, privacy: .public)")
                return nil
            }
            return QRToken(hex: cached.hex, expiresAt: cached.expiresAt)
        } catch {
            AppLog.flow.error("loadQRToken failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func persistCachedToken(_ token: QRToken) {
        do {
            try KeychainStore.saveQRToken(.init(hex: token.hex, expiresAt: token.expiresAt))
        } catch {
            AppLog.flow.error("saveQRToken failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func scheduleExpiryRefresh(expiresAt: Date) {
        refreshTask?.cancel()
        let interval = expiresAt.timeIntervalSinceNow - refreshLeadTime
        AppLog.flow.info("refresh scheduled in \(String(format: "%.0f", interval), privacy: .public) s")
        refreshTask = Task { [weak self] in
            guard interval > 0 else {
                await self?.silentRefresh(reason: "lead-time-passed")
                return
            }
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }
            await self?.silentRefresh(reason: "expiry-timer")
        }
    }

    // MARK: - Error formatting

    private static func describeRefresh(error: Error) -> String {
        switch error {
        case let e as AuthError: return describe(authError: e)
        case let e as QRError: return describe(qrError: e)
        default: return error.localizedDescription
        }
    }

    private static func describe(authError: AuthError) -> String {
        switch authError {
        case .noCredentials:
            return String(localized: "No saved sign-in.", bundle: .module)
        case .invalidCredentials:
            return String(localized: "Incorrect email or password.", bundle: .module)
        case .network(let e):
            return String(localized: "Network error: \(e.localizedDescription)", bundle: .module)
        case .unexpected(let status):
            return String(localized: "Server returned HTTP \(status).", bundle: .module)
        case .encoding:
            return String(localized: "Couldn't encode the request.", bundle: .module)
        case .decoding:
            return String(localized: "Couldn't decode the response.", bundle: .module)
        case .jwt(let e):
            return String(localized: "Invalid token: \(String(describing: e))", bundle: .module)
        case .missingToken:
            return String(localized: "Server didn't return a token.", bundle: .module)
        }
    }

    private static func describe(qrError: QRError) -> String {
        switch qrError {
        case .network(let e):
            return String(localized: "Network error: \(e.localizedDescription)", bundle: .module)
        case .unexpected(let status):
            return String(localized: "Server returned HTTP \(status).", bundle: .module)
        case .decoding:
            return String(localized: "Couldn't decode the QR response.", bundle: .module)
        case .dataURLMalformed:
            return String(localized: "Couldn't read the QR data URL.", bundle: .module)
        case .pngDecodeFailed:
            return String(localized: "Couldn't decode the QR image.", bundle: .module)
        case .qrNotFound:
            return String(localized: "No QR code found in the image.", bundle: .module)
        }
    }
}

