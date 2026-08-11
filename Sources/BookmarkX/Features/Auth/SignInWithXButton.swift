import SwiftUI

/// Primary “Sign in with X” control used on onboarding and settings.
struct SignInWithXButton: View {
    var isLoading: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.black))
                }
                Text(isLoading ? "settings.connectingX" : "auth.signInWithX")
                    .font(.headline)
            }
            .frame(maxWidth: 320)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isLoading ? 0.7 : 1)
        .disabled(isLoading)
        .accessibilityLabel(Text("auth.signInWithX"))
    }
}
