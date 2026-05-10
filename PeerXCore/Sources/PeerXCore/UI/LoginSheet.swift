import SwiftUI

public struct LoginSheet: View {
    public typealias Submit = @MainActor (_ email: String, _ password: String) -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @FocusState private var focus: Field?
    let onSubmit: Submit

    public init(onSubmit: @escaping Submit) {
        self.onSubmit = onSubmit
    }

    enum Field { case email, password }

    public var body: some View {
        VStack(spacing: 0) {
            titleBlock
                .padding(.top, Spacing.hero)

            formBlock
                .padding(.top, Spacing.large)

            primaryAction
                .padding(.top, Spacing.group)

            Spacer(minLength: Spacing.large)

            footerNote
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Blocks

    private var titleBlock: some View {
        VStack(spacing: Spacing.group) {
            PeerXLogoMark()
                .frame(width: 96, height: 96)

            VStack(spacing: 6) {
                Text(verbatim: "PeerX")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .kerning(-1.0)
                Text("Sign in to your 21 School Applicant", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var formBlock: some View {
        VStack(spacing: Spacing.element) {
            glassField(
                icon: "envelope",
                placeholder: Text("Email", bundle: .module),
                text: $email,
                isSecure: false,
                contentType: .username,
                keyboard: .emailAddress,
                focusBinding: .email
            )

            glassField(
                icon: "lock",
                placeholder: Text("Password", bundle: .module),
                text: $password,
                isSecure: true,
                contentType: .password,
                keyboard: .default,
                focusBinding: .password
            )
        }
    }

    private var primaryAction: some View {
        Button {
            focus = nil
            isSubmitting = true
            onSubmit(email, password)
        } label: {
            Group {
                if isSubmitting {
                    ProgressView().tint(.black)
                } else {
                    Text("Sign In", bundle: .module)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: ControlSize.height)
            .foregroundStyle(.black)
        }
        .background(
            (canSubmit ? Color.white : Color.white.opacity(0.4)),
            in: .rect(cornerRadius: Radius.button)
        )
        .disabled(!canSubmit)
    }

    private var footerNote: some View {
        Text(
            "Your credentials stay in your device's Keychain.\nThey're sent only when you sign in.",
            bundle: .module
        )
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.35))
        .multilineTextAlignment(.center)
        .padding(.bottom, Spacing.element)
    }

    private var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !isSubmitting
    }

    // MARK: - Field

    @ViewBuilder
    private func glassField(
        icon: String,
        placeholder: Text,
        text: Binding<String>,
        isSecure: Bool,
        contentType: UITextContentType,
        keyboard: UIKeyboardType,
        focusBinding: Field
    ) -> some View {
        HStack(spacing: Spacing.element) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 22)

            Group {
                if isSecure {
                    SecureField("", text: text, prompt: placeholder.foregroundStyle(.white.opacity(0.4)))
                        .textContentType(contentType)
                } else {
                    TextField("", text: text, prompt: placeholder.foregroundStyle(.white.opacity(0.4)))
                        .textContentType(contentType)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .focused($focus, equals: focusBinding)
            .foregroundStyle(.white)
            .tint(.white)
        }
        .padding(.horizontal, Spacing.group)
        .frame(height: ControlSize.height)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.field))
    }
}
