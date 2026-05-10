import Foundation

public enum Constants {
    public static let apiBaseURL = URL(string: "https://applicant.21-school.ru")!

    public static let passTypeIdentifier = "pass.me.nickaroot.peerx"
    public static let teamIdentifier = "MYKD6MLV98"
    public static let organizationName = "ALEXEY KOMAROV"

    public static let keychainService = "me.nickaroot.peerx"
    public static let keychainAccessGroup = "$(AppIdentifierPrefix)me.nickaroot.peerx"

    public static let aasaHost = "peerx.org"

    /// App Store ADAM ID for `associatedStoreIdentifiers` on the pass back side.
    /// Use "0" until the parent app is published.
    public static let parentAppADAMID = "6767598606"

    /// `appLaunchURL` on the pass back side. Parent matches this prefix in
    /// `.onOpenURL` and triggers `silentRefresh()`.
    public static let walletRefreshURL = "https://peerx.org/wallet-refresh"
}
