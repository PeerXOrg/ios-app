import ProjectDescription

let teamID = "MYKD6MLV98"
let parentBundleID = "me.nickaroot.peerx"
let clipBundleID = "me.nickaroot.peerx.Clip"
let deploymentTarget: DeploymentTargets = .iOS("26.4")

let baseSettings: SettingsDictionary = [
    "DEVELOPMENT_TEAM": .string(teamID),
    "SWIFT_VERSION": "6.0",
    "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
    "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
    "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "STRING_CATALOG_GENERATE_SYMBOLS": "YES",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
]

let parentInfoPlist: [String: Plist.Value] = [
    "CFBundleLocalizations": .array([.string("en"), .string("ru")]),
    "ITSAppUsesNonExemptEncryption": .boolean(false),
    "UIApplicationSceneManifest_Generation": .boolean(true),
    "UIApplicationSupportsIndirectInputEvents": .boolean(true),
    "UILaunchScreen_Generation": .boolean(true),
    "UIStatusBarStyle": "UIStatusBarStyleDefault",
    "UISupportedInterfaceOrientations": .array([.string("UIInterfaceOrientationPortrait")]),
    "UIUserInterfaceStyle": "Dark",
]

let parent = Target.target(
    name: "PeerX",
    destinations: .iOS,
    product: .app,
    bundleId: parentBundleID,
    deploymentTargets: deploymentTarget,
    infoPlist: .extendingDefault(with: parentInfoPlist),
    sources: ["PeerX/**"],
    resources: [
        "PeerX/Assets.xcassets",
        "PeerX/InfoPlist.xcstrings",
    ],
    entitlements: .file(path: "PeerX/PeerX.entitlements"),
    dependencies: [
        .package(product: "PeerXCore"),
        .target(name: "PeerXClip"),
    ],
    settings: .settings(
        base: baseSettings.merging([
            "MARKETING_VERSION": "1.0",
            "CURRENT_PROJECT_VERSION": "1",
            "TARGETED_DEVICE_FAMILY": "1",
            "ENABLE_APP_SANDBOX": "YES",
            "ENABLE_HARDENED_RUNTIME": "YES",
            "ENABLE_USER_SELECTED_FILES": "readonly",
            "REGISTER_APP_GROUPS": "YES",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        ])
    )
)

let clipInfoPlist: [String: Plist.Value] = [
    "CFBundleDisplayName": "PeerX",
    "CFBundleLocalizations": .array([.string("en"), .string("ru")]),
    "UIApplicationSceneManifest_Generation": .boolean(true),
    "UIApplicationSupportsIndirectInputEvents": .boolean(true),
    "UILaunchScreen_Generation": .boolean(true),
    "UISupportedInterfaceOrientations": .array([.string("UIInterfaceOrientationPortrait")]),
    "UIUserInterfaceStyle": "Dark",
    "NSAppClip": .dictionary([
        "NSAppClipRequestEphemeralUserNotification": .boolean(false),
        "NSAppClipRequestLocationConfirmation": .boolean(false),
    ]),
]

let clip = Target.target(
    name: "PeerXClip",
    destinations: .iOS,
    product: .appClip,
    bundleId: clipBundleID,
    deploymentTargets: deploymentTarget,
    infoPlist: .extendingDefault(with: clipInfoPlist),
    sources: ["PeerXClip/**"],
    resources: [
        "PeerXClip/Assets.xcassets",
        "PeerXClip/InfoPlist.xcstrings",
    ],
    entitlements: .file(path: "PeerXClip/PeerXClip.entitlements"),
    dependencies: [
        .package(product: "PeerXCore"),
    ],
    settings: .settings(
        base: baseSettings.merging([
            "MARKETING_VERSION": "1.0",
            "CURRENT_PROJECT_VERSION": "1",
            "TARGETED_DEVICE_FAMILY": "1",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        ])
    )
)

let project = Project(
    name: "PeerX",
    options: .options(
        defaultKnownRegions: ["en", "ru", "Base"],
        developmentRegion: "en"
    ),
    packages: [
        .local(path: "PeerXCore"),
    ],
    settings: .settings(base: baseSettings),
    targets: [parent, clip]
)
