import SwiftUI

/// Every badge: earned ones first, then the locked ones with their progress.
struct BadgesView: View {
    let stats: HabitStats

    private var ordered: [Badge] {
        let earned = stats.badges.filter(\.isUnlocked).sorted { $0.tier > $1.tier }
        let locked = stats.badges.filter { !$0.isUnlocked }.sorted { $0.tier < $1.tier }
        return earned + locked
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("\(stats.badges.filter(\.isUnlocked).count) of \(stats.badges.count) earned")
                GlassGroup {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, badge in
                        if index > 0 { InsetDivider() }
                        BadgeRow(badge: badge)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background { AmbientBackground(variant: .streaks) }
        .navigationTitle("Badges")
        .navigationBarTitleDisplayMode(.large)
        .toolbarVisibility(.visible, for: .navigationBar)
    }
}
