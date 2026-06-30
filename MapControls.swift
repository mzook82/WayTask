import SwiftUI

struct MapControls: View {
    let onFollowUser: () -> Void
    let onAddLocation: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            controlButton(
                systemName: "location.fill",
                label: "Follow current location",
                prominent: true,
                action: onFollowUser
            )
            controlButton(
                systemName: "plus",
                label: "Add location",
                prominent: false,
                action: onAddLocation
            )
        }
    }

    private func controlButton(systemName: String, label: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(prominent ? .white : .primary)
                .frame(width: 50, height: 50)
                .background {
                    if prominent {
                        WayTaskDesign.accentGradient
                    } else {
                        Color.clear.background(.ultraThinMaterial)
                    }
                }
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
