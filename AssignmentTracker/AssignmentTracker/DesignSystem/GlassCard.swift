import SwiftUI

extension View {
    /// A rounded Liquid Glass surface, used for every card in the mockups.
    func glassCard(cornerRadius: CGFloat = 22, interactive: Bool = false) -> some View {
        glassEffect(
            interactive ? .regular.interactive() : .regular,
            in: .rect(cornerRadius: cornerRadius)
        )
    }
}
