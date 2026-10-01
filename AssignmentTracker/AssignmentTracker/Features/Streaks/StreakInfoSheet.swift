import SwiftUI

/// How the streak is counted, moved off the main screen into the ⓘ button.
struct StreakInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let rules: [(symbol: String, text: String)] = [
        ("checkmark.circle.fill", "Finish an assignment before its due time and your streak grows by one."),
        ("arrow.counterclockwise", "Finishing late, or letting something go overdue, starts the streak again."),
        ("clock", "Work that isn’t due yet never breaks a streak, even if it’s still open."),
        ("square.and.arrow.down", "Work added after it was already due, like past items from a syllabus import, doesn’t count either way."),
        ("calendar.badge.checkmark", "A perfect week is a Monday-to-Sunday week where everything due was finished on time."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Finish work before its due time to grow your streak. Work added after it was due doesn’t count either way.")
                        .font(.body)
                    GlassGroup {
                        ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                            if index > 0 { InsetDivider(leading: 52) }
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: rule.symbol)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Palette.streakOrange)
                                    .frame(width: 26)
                                Text(rule.text)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .navigationTitle("How Streaks Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
