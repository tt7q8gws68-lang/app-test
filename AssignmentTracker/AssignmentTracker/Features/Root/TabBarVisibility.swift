import Observation
import SwiftUI

/// Whether the floating tab bar shows. Pushed screens (Assignment Detail, Badges) hide it while
/// they're on screen; a counter keeps nested pushes from showing it too early.
@Observable
final class TabBarVisibility {
    private var hiders = 0

    var isVisible: Bool { hiders == 0 }

    func hide() { hiders += 1 }
    func show() { hiders = max(0, hiders - 1) }
}

extension EnvironmentValues {
    /// Extra bottom room a tab's scroll view needs to end clear of the floating tab bar.
    @Entry var tabBarClearance: CGFloat = 0
}

extension View {
    /// Adds bottom room so scrolling content ends clear of the floating tab bar.
    func clearsTabBar() -> some View {
        modifier(ClearsTabBar())
    }

    /// Hides the floating tab bar while this view is on screen.
    func hidesTabBar() -> some View {
        modifier(HidesTabBar())
    }
}

private struct HidesTabBar: ViewModifier {
    @Environment(TabBarVisibility.self) private var visibility: TabBarVisibility?
    @State private var isHiding = false

    func body(content: Content) -> some View {
        content
            .toolbarVisibility(.hidden, for: .tabBar)
            .onAppear {
                guard !isHiding else { return }
                isHiding = true
                withAnimation(.snappy) { visibility?.hide() }
            }
            .onDisappear {
                guard isHiding else { return }
                isHiding = false
                withAnimation(.snappy) { visibility?.show() }
            }
    }
}

private struct ClearsTabBar: ViewModifier {
    @Environment(\.tabBarClearance) private var clearance

    func body(content: Content) -> some View {
        content.contentMargins(.bottom, clearance, for: .scrollContent)
    }
}
