import SwiftUI

public struct MainFlowView: View {
    @State private var model = MainFlowModel()
    @State private var walletError: String?
    @State private var sharePassURL: URL?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AmbientBackground()
            // `.containerRelativeFrame(.horizontal)` is the only modifier
            // that clamps content under iOS 26 when `.frame(maxWidth: .infinity)`
            // is combined with `.glassEffect(_:in:)` / `.background(_:in:)`.
            contentBody
                .containerRelativeFrame(.horizontal) { length, _ in
                    max(0, length - Spacing.edge * 2)
                }
                .animation(
                    reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.88),
                    value: stateKind
                )
        }
        .preferredColorScheme(.dark)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task { await model.silentRefresh() }
                model.resumeAutoRefresh()
            case .background, .inactive:
                model.cancelAutoRefresh()
            @unknown default:
                break
            }
        }
        .onOpenURL { url in
            AppLog.flow.info("onOpenURL \(url.absoluteString, privacy: .public)")
            if url.absoluteString.hasPrefix(Constants.walletRefreshURL) {
                Task { await model.silentRefresh() }
            }
        }
        .alert(Text("Wallet", bundle: .module), isPresented: Binding(
            get: { walletError != nil },
            set: { if !$0 { walletError = nil } }
        )) {
            Button {
                walletError = nil
            } label: {
                Text("OK", bundle: .module)
            }
        } message: {
            Text(walletError ?? "")
        }
        .alert(Text("Couldn't refresh", bundle: .module), isPresented: Binding(
            get: { model.refreshError != nil },
            set: { if !$0 { model.refreshError = nil } }
        )) {
            Button {
                model.refreshError = nil
            } label: {
                Text("OK", bundle: .module)
            }
        } message: {
            Text(model.refreshError ?? "")
        }
        .sheet(item: $sharePassURL) { url in
            ShareSheet(items: [url])
        }
    }

    private var stateKind: Int {
        switch model.state {
        case .idle, .loadingCreds: return 0
        case .needsLogin:           return 1
        case .signingIn:            return 2
        case .refreshingQR:         return 3
        case .buildingPass:         return 4
        case .ready:                return 5
        case .failed:               return 6
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch model.state {
        case .idle, .loadingCreds:
            statusView(systemImage: "circle.dotted", title: Text("Loading…", bundle: .module))
                .transition(.softFade)
        case .needsLogin:
            LoginSheet { email, password in
                Task { await model.handleLogin(email: email, password: password) }
            }
            .transition(.softFade)
        case .signingIn(let email):
            statusView(
                systemImage: "person.circle",
                title: email.isEmpty
                    ? Text("Signing in…", bundle: .module)
                    : Text("Signing in as \(email)…", bundle: .module)
            )
            .transition(.softFade)
        case .refreshingQR:
            statusView(systemImage: "qrcode", title: Text("Refreshing QR code…", bundle: .module))
                .transition(.softFade)
        case .buildingPass:
            statusView(systemImage: "wallet.pass", title: Text("Preparing your pass…", bundle: .module))
                .transition(.softFade)
        case .ready(let token, let passData):
            readyView(token: token, passData: passData)
                .transition(.softFade)
        case .failed(let message):
            failedView(message: message)
                .transition(.softFade)
        }
    }

    private func statusView(systemImage: String, title: Text) -> some View {
        VStack(spacing: Spacing.group) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
            ProgressView()
                .controlSize(.regular)
                .tint(.white)
            title
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: Spacing.group) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white)
            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            VStack(spacing: Spacing.element) {
                Button {
                    Task { await model.start() }
                } label: {
                    Text("Try Again", bundle: .module)
                        .frame(maxWidth: .infinity)
                        .frame(height: ControlSize.height)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                }
                .background(.white, in: .rect(cornerRadius: Radius.button))

                Button {
                    Task { await model.signOut() }
                } label: {
                    Text("Switch Account", bundle: .module)
                        .frame(maxWidth: .infinity)
                        .frame(height: ControlSize.height)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                }
                .glassEffect(.regular, in: .rect(cornerRadius: Radius.button))
            }
            .padding(.top, Spacing.tight)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func readyView(token: QRToken, passData: Data?) -> some View {
        VStack(spacing: Spacing.section) {
            VStack(spacing: 4) {
                Text(verbatim: "PeerX")
                    .font(.system(size: 34, weight: .bold, design: .default))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .kerning(-1.0)
                Text("21 School • Vyatskaya", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }

            qrCard(message: token.hex)

            Text(expiryText(token.expiresAt))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))

            actionButtons(passData: passData)

            secondaryActions(passData: passData)
        }
        .frame(maxWidth: .infinity)
    }

    private func qrCard(message: String) -> some View {
        QRCodeView(message: message)
            .frame(maxWidth: 280, maxHeight: 280)
            .padding(Spacing.group)
            .background(.white, in: .rect(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .white.opacity(0.05), radius: 24, y: 8)
            .background {
                BreathingHalo()
            }
    }

    private func actionButtons(passData: Data?) -> some View {
        VStack(spacing: Spacing.element) {
            if let data = passData {
                AddPassToWalletButton(style: .blackOutline) {
                    AppLog.flow.info("Wallet button tapped passData=\(data.count) B")
                    Task {
                        let result = await PassAdder.add(passData: data)
                        if case .failure(let err) = result, err != .userCancelled {
                            walletError = err.localizedDescription
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: ControlSize.height)
            }

            Button {
                Task { await model.manualRefresh() }
            } label: {
                Group {
                    if model.isManualRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Label {
                            Text("Refresh", bundle: .module)
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: ControlSize.height)
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.button))
            .disabled(model.isManualRefreshing)
        }
    }

    private func secondaryActions(passData: Data?) -> some View {
        VStack(spacing: Spacing.tight) {
            if let data = passData {
                Button {
                    sharePassURL = writePassToTemp(data)
                } label: {
                    Label {
                        Text("Share .pkpass", bundle: .module)
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await model.signOut() }
            } label: {
                Text("Sign Out", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, Spacing.tight)
    }

    private func expiryText(_ date: Date) -> String {
        let formatted = date.formatted(date: .abbreviated, time: .shortened)
        return String(localized: "Valid until \(formatted)", bundle: .module)
    }

    private func writePassToTemp(_ data: Data) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PeerX.pkpass")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            walletError = String(
                localized: "Couldn't save the file: \(error.localizedDescription)",
                bundle: .module
            )
            return nil
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Animation primitives

private struct AmbientBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            blob(
                color: Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.22),
                offset: animate ? CGSize(width:  60, height: -80) : CGSize(width: -60, height:  80),
                duration: 14
            )
            blob(
                color: Color(red: 236/255, green: 72/255, blue: 153/255).opacity(0.16),
                offset: animate ? CGSize(width: -90, height:  70) : CGSize(width:  90, height: -70),
                duration: 18
            )
            blob(
                color: Color(red: 34/255, green: 211/255, blue: 238/255).opacity(0.10),
                offset: animate ? CGSize(width:  40, height:  50) : CGSize(width: -40, height: -50),
                duration: 21
            )
        }
        .blur(radius: 100)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            animate = true
        }
    }

    private func blob(color: Color, offset: CGSize, duration: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: 520, height: 520)
            .offset(offset)
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: duration).repeatForever(autoreverses: true),
                value: animate
            )
    }
}

private struct BreathingHalo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .blur(radius: 50)
            Circle()
                .fill(Color(red: 99/255, green: 102/255, blue: 241/255).opacity(0.18))
                .blur(radius: 70)
                .offset(x: animate ? 18 : -18, y: animate ? -12 : 12)
        }
        .frame(width: 380, height: 380)
        .scaleEffect(animate ? 1.06 : 1.0)
        .opacity(animate ? 1.0 : 0.78)
        .animation(
            reduceMotion
                ? nil
                : .easeInOut(duration: 4).repeatForever(autoreverses: true),
            value: animate
        )
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            animate = true
        }
    }
}

private extension AnyTransition {
    static var softFade: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98)),
            removal: .opacity.combined(with: .scale(scale: 1.02))
        )
    }
}
