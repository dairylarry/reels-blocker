import SwiftUI

/// Persistent strip across the top: which build you're on, and the way in to
/// Diagnostics.
///
/// It sits in a `safeAreaInset`, not an overlay, so it never covers
/// Instagram's own header — the web view simply starts below it.
///
/// Turns amber and names the rule when a premise assertion is failing, which
/// is the one moment it has something urgent to say (architecture §7.6.1).
struct VersionBanner: View {
    var alert: String?
    var openDiagnostics: () -> Void

    private var failing: Bool { alert != nil }

    var body: some View {
        HStack(spacing: 6) {
            if failing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
            }
            Text(failing ? alert! : AppVersion.display)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            Button(action: openDiagnostics) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Diagnostics")
        }
        .foregroundStyle(.white.opacity(0.95))
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .background(failing ? Color.orange.opacity(0.95) : Color.black.opacity(0.85))
        .animation(.easeInOut(duration: 0.25), value: failing)
    }
}
