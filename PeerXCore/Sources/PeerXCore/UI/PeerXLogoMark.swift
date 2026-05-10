import SwiftUI

public struct PeerXLogoMark: View {
    let animated: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false
    @State private var halo = false

    public init(animated: Bool = true) {
        self.animated = animated
    }

    public var body: some View {
        ZStack {
            haloLayer
            glyphLayer
                .shadow(color: .white.opacity(0.18), radius: 12, y: 4)
        }
        .onAppear {
            guard shouldAnimate else { return }
            drift = true
            halo = true
        }
    }

    private var glyphLayer: some View {
        ZStack {
            Image("PeerXLogoTop", bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .offset(y: shouldAnimate && drift ? -3 : 0)
                .animation(
                    shouldAnimate
                        ? .easeInOut(duration: 2.25).repeatForever(autoreverses: true)
                        : nil,
                    value: drift
                )

            Image("PeerXLogoBottom", bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .offset(y: shouldAnimate && drift ? 3 : 0)
                .animation(
                    shouldAnimate
                        ? .easeInOut(duration: 2.25).repeatForever(autoreverses: true)
                        : nil,
                    value: drift
                )
        }
    }

    private var haloLayer: some View {
        Circle()
            .fill(Color.white.opacity(0.22))
            .blur(radius: 28)
            .scaleEffect(shouldAnimate && halo ? 1.18 : 1.0)
            .opacity(shouldAnimate && halo ? 1.0 : 0.55)
            .animation(
                shouldAnimate
                    ? .easeInOut(duration: 2.5).repeatForever(autoreverses: true)
                    : nil,
                value: halo
            )
            .scaleEffect(1.72)
            .allowsHitTesting(false)
    }

    private var shouldAnimate: Bool {
        animated && !reduceMotion
    }
}
