import SwiftUI
import PassKit

/// SwiftUI wrapper around `PKAddPassButton` — Apple's branded
/// "Add to Apple Wallet" control with auto-localised artwork.
struct AddPassToWalletButton: UIViewRepresentable {
    let style: PKAddPassButtonStyle
    let cornerRadius: CGFloat
    let action: () -> Void

    init(
        style: PKAddPassButtonStyle,
        cornerRadius: CGFloat = Radius.button,
        action: @escaping () -> Void
    ) {
        self.style = style
        self.cornerRadius = cornerRadius
        self.action = action
    }

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: style)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.layer.cornerRadius = cornerRadius
        button.layer.masksToBounds = true
        button.addAction(
            UIAction { [action] _ in action() },
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) {
        uiView.layer.cornerRadius = cornerRadius
    }
}
