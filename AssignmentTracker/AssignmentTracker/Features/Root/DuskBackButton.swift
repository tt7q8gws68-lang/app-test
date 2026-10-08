import SwiftUI
import UIKit

extension View {
    /// Replaces the system back button with the app's glass back button (the set's back icon),
    /// keeping the edge swipe-back gesture.
    func duskBackButton() -> some View {
        modifier(DuskBackButton())
    }
}

private struct DuskBackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    GlassCircleButton(icon: .back, label: "Back") { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
            }
    }
}

/// Hiding the system back button turns off the edge swipe in SwiftUI; this re-enables it for any
/// stack deeper than its root.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Not mid-push or mid-pop: starting a swipe then can freeze the stack.
        viewControllers.count > 1 && transitionCoordinator == nil
    }
}
