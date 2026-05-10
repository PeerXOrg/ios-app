import SwiftUI
import PeerXCore
import os

struct ContentView: View {
    @State private var invocationURL: URL?

    var body: some View {
        MainFlowView()
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                invocationURL = activity.webpageURL
                AppLog.flow.info("Clip invoked via URL: \(activity.webpageURL?.absoluteString ?? "<nil>", privacy: .public)")
                // TODO: parse query params (e.g. ?campus=...) for multi-campus support.
            }
    }
}

#Preview {
    ContentView()
}
