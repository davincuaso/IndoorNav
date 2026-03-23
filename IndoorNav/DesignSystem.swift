import SwiftUI

// MARK: - Color Palette

extension Color {
    static let appPrimary = Color.blue
    static let appSecondary = Color.cyan
    static let appAccent = Color.green

    static let mapMode = Color.blue
    static let navMode = Color.green
    static let scanMode = Color.purple

    static let destination = Color.blue
    static let waypoint = Color.yellow
    static let path = Color.cyan
    static let arrived = Color.green
}

// MARK: - Typography

extension Font {
    static let appTitle = Font.system(.title, design: .rounded, weight: .bold)
    static let appHeadline = Font.system(.headline, design: .rounded, weight: .semibold)
    static let appSubheadline = Font.system(.subheadline, design: .rounded, weight: .medium)
    static let appBody = Font.system(.body, design: .rounded)
    static let appCaption = Font.system(.caption, design: .rounded)
    static let appCaption2 = Font.system(.caption2, design: .rounded)
}

// MARK: - Common View Modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

struct GlassStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct PillButtonStyle: ButtonStyle {
    var color: Color = .appPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.appSubheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1))
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    func glassStyle() -> some View {
        modifier(GlassStyle())
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    enum Status {
        case active
        case inactive
        case warning
        case error

        var color: Color {
            switch self {
            case .active: return .green
            case .inactive: return .gray
            case .warning: return .yellow
            case .error: return .red
            }
        }
    }

    let status: Status
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.appCaption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String
    var iconColor: Color = .appPrimary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(iconColor)
                .frame(width: 20)

            Text(title)
                .font(.appCaption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.appCaption)
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(message)
                .font(.appCaption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)?
    var actionTitle: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(title)
                    .font(.appHeadline)

                Text(message)
                    .font(.appCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let action = action, let title = actionTitle {
                Button(action: action) {
                    Text(title)
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .padding()
    }
}

// MARK: - Tab Bar Configuration

enum AppTab: String, CaseIterable, Identifiable {
    case ar = "AR"
    case scans = "Scans"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ar: return "AR Navigation"
        case .scans: return "My Scans"
        }
    }

    var icon: String {
        switch self {
        case .ar: return "arkit"
        case .scans: return "cube.transparent"
        }
    }

    var selectedIcon: String {
        switch self {
        case .ar: return "arkit"
        case .scans: return "cube.fill"
        }
    }

    var color: Color {
        switch self {
        case .ar: return .appPrimary
        case .scans: return .scanMode
        }
    }
}
