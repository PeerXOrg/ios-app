import UIKit
import PassKit

public enum PassPresentError: Error, LocalizedError, Sendable, Equatable {
    case libraryUnavailable
    case parseFailed(underlying: String)
    case viewControllerInitFailed
    case userCancelled

    public var errorDescription: String? {
        switch self {
        case .libraryUnavailable:
            return String(localized: "Wallet isn't available on this device.", bundle: .module)
        case .parseFailed(let s):
            return String(localized: "Wallet couldn't read the pass: \(s)", bundle: .module)
        case .viewControllerInitFailed:
            return String(
                localized: "Wallet couldn't accept the pass. It might already be added or have an invalid signature.",
                bundle: .module
            )
        case .userCancelled:
            return String(localized: "Cancelled", bundle: .module)
        }
    }
}

public enum PassAdder {
    /// Replaces an existing Wallet pass with the same
    /// `(passTypeIdentifier, serialNumber)`. Returns `false` if no
    /// matching pass is installed. No UI is shown.
    @MainActor
    public static func replaceIfPresent(passData: Data) async -> Bool {
        guard PKPassLibrary.isPassLibraryAvailable() else { return false }

        let pass: PKPass
        do {
            pass = try PKPass(data: passData)
        } catch {
            AppLog.pass.error("replaceIfPresent PKPass parse failed: \(String(describing: error), privacy: .public)")
            return false
        }

        let library = PKPassLibrary()
        guard let existing = library.pass(withPassTypeIdentifier: pass.passTypeIdentifier ?? "", serialNumber: pass.serialNumber),
              existing.serialNumber == pass.serialNumber
        else {
            return false
        }

        let replaced = library.replacePass(with: pass)
        AppLog.pass.info("replaceIfPresent replaced=\(replaced, privacy: .public) serial=\(pass.serialNumber, privacy: .public)")
        return replaced
    }

    /// Adds a pass via `PKPassLibrary.addPasses` (Wallet-daemon UI, survives
    /// Lockdown Mode). Falls back to `PKAddPassesViewController` when the
    /// system requires user review.
    @MainActor
    public static func add(passData: Data) async -> Result<Void, PassPresentError> {
        AppLog.pass.info("PassAdder.add start (\(passData.count) B)")

        guard PKPassLibrary.isPassLibraryAvailable() else {
            AppLog.pass.error("PKPassLibrary not available")
            return .failure(.libraryUnavailable)
        }

        let pass: PKPass
        do {
            pass = try PKPass(data: passData)
            AppLog.pass.info("PKPass parsed serial=\(pass.serialNumber, privacy: .public) typeID=\(pass.passTypeIdentifier ?? "?", privacy: .public)")
        } catch {
            AppLog.pass.error("PKPass(data:) failed: \(String(describing: error), privacy: .public) — \(error.localizedDescription, privacy: .public)")
            return .failure(.parseFailed(underlying: error.localizedDescription))
        }

        let library = PKPassLibrary()
        let wrapped = SendablePass(pass: pass)

        let status: PKPassLibraryAddPassesStatus = await withCheckedContinuation { cont in
            library.addPasses([wrapped.pass]) { status in
                cont.resume(returning: status)
            }
        }

        switch status {
        case .didAddPasses:
            AppLog.pass.info("PKPassLibrary.didAddPasses ✓")
            return .success(())
        case .shouldReviewPasses:
            AppLog.pass.info("PKPassLibrary.shouldReviewPasses — presenting PKAddPassesViewController")
            return await presentReviewController(for: wrapped)
        case .didCancelAddPasses:
            AppLog.pass.info("PKPassLibrary.didCancelAddPasses")
            return .failure(.userCancelled)
        @unknown default:
            AppLog.pass.error("PKPassLibrary unknown status: \(String(describing: status), privacy: .public)")
            return .failure(.viewControllerInitFailed)
        }
    }

    @MainActor
    private static func presentReviewController(for wrapped: SendablePass) async -> Result<Void, PassPresentError> {
        guard let topVC = topmostViewController() else {
            AppLog.pass.error("No topmost VC for PKAddPassesViewController fallback")
            return .failure(.viewControllerInitFailed)
        }
        guard let addVC = PKAddPassesViewController(pass: wrapped.pass) else {
            AppLog.pass.error("PKAddPassesViewController init returned nil")
            return .failure(.viewControllerInitFailed)
        }

        let delegate = AddPassDelegate()
        addVC.delegate = delegate

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            delegate.onFinish = {
                addVC.dismiss(animated: true) { cont.resume() }
            }
            topVC.present(addVC, animated: true) {
                AppLog.pass.info("PKAddPassesViewController presented (review fallback)")
            }
        }

        _ = delegate
        return .failure(.userCancelled)
    }

    @MainActor
    private static func topmostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first else {
            return nil
        }
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private struct SendablePass: @unchecked Sendable {
        let pass: PKPass
    }
}

@MainActor
private final class AddPassDelegate: NSObject, @preconcurrency PKAddPassesViewControllerDelegate {
    var onFinish: (() -> Void)?

    func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
        AppLog.pass.info("AddPassesViewController finished")
        onFinish?()
    }
}
