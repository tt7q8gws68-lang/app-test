import SwiftUI

/// Motivation: the on-time streak, a few stats, a 12-week activity grid and badges to unlock.
struct StreaksView: View {
    let stats: HabitStats

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    StreakHero(stats: stats)

                    HStack(spacing: 12) {
                        StatTile(
                            value: stats.onTimeRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
                            label: "On time, 30 days"
                        )
                        StatTile(value: "\(stats.perfectWeeks)", label: "Perfect weeks")
                        StatTile(value: "\(stats.earlyFinishes)", label: "Done early")
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Last 12 weeks")
                        ActivityHeatmap(activity: stats.activity)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader("Badges")
                        BadgeGrid(badges: stats.badges)
                    }

                    Text("Finish work before its due time to grow your streak. Work added after it was due doesn’t count either way.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryText)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background { AmbientBackground(variant: .list) }
            .navigationTitle("Streaks")
        }
    }
}

private struct StreakHero: View {
    let stats: HabitStats

    private var message: String {
        if stats.allDoneToday { return "Everything due today is done." }
        if stats.openToday > 0 {
            return stats.openToday == 1 ? "1 thing due today keeps it going." : "\(stats.openToday) things due today keep it going."
        }
        if stats.currentStreak == 0 { return "Finish your next assignment on time to start a streak." }
        return "Keep finishing before the deadline."
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 52))
                .foregroundStyle(stats.currentStreak > 0 ? AnyShapeStyle(.orange.gradient) : AnyShapeStyle(Palette.chevron))
                .symbolEffect(.bounce, value: stats.currentStreak)
            Text("\(stats.currentStreak)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text("on time in a row")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
            if stats.bestStreak > 0 {
                Label("Best: \(stats.bestStreak)", systemImage: "trophy.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .glassEffect(.regular, in: .capsule)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .glassCard(cornerRadius: 28)
        .animation(.snappy, value: stats.currentStreak)
        .accessibilityElement(children: .combine)
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

/// A GitHub-style grid: one column per week, one square per day, darker for more work
/// finished on time that day.
private struct ActivityHeatmap: View {
    let activity: [Date: Int]

    private let calendar = Calendar.current
    private static let weeks = 12

    private var columns: [[Date]] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)!.start
        let first = calendar.date(byAdding: .weekOfYear, value: -(Self.weeks - 1), to: thisWeek)!
        return (0..<Self.weeks).map { week in
            (0..<7).map { calendar.date(byAdding: .day, value: week * 7 + $0, to: first)! }
        }
    }

    var body: some View {
        let today = calendar.startOfDay(for: .now)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(columns, id: \.first) { week in
                    VStack(spacing: 4) {
                        ForEach(week, id: \.self) { day in
                            let count = activity[day] ?? 0
                            RoundedRectangle(cornerRadius: 4)
                                .fill(day > today ? AnyShapeStyle(.clear) : AnyShapeStyle(fill(for: count)))
                                .overlay {
                                    if day == today {
                                        RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor, lineWidth: 1.5)
                                    }
                                }
                                .aspectRatio(1, contentMode: .fit)
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Text("Less")
                ForEach([0, 1, 2, 3], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3).fill(fill(for: level)).frame(width: 12, height: 12)
                }
                Text("More")
                Spacer()
                Text("\(activity.values.reduce(0, +)) on time")
            }
            .font(.caption2)
            .foregroundStyle(Palette.secondaryText)
        }
        .padding(16)
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity over the last 12 weeks")
        .accessibilityValue("\(activity.values.reduce(0, +)) assignments finished on time on \(activity.count) days")
    }

    private func fill(for count: Int) -> Color {
        switch count {
        case 0: Palette.track
        case 1: Palette.success.opacity(0.4)
        case 2: Palette.success.opacity(0.7)
        default: Palette.success
        }
    }
}

private struct BadgeGrid: View {
    let badges: [Badge]

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(badges) { badge in
                HStack(spacing: 12) {
                    Image(systemName: badge.isUnlocked ? badge.systemImage : "lock.fill")
                        .font(.title3)
                        .foregroundStyle(badge.isUnlocked ? AnyShapeStyle(.orange.gradient) : AnyShapeStyle(Palette.chevron))
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(badge.isUnlocked ? .primary : Palette.secondaryText)
                        Text(badge.detail)
                            .font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity, alignment: .leading)
                .padding(12)
                .glassCard(cornerRadius: 18)
                .accessibilityElement(children: .combine)
                .accessibilityValue(badge.isUnlocked ? "Unlocked" : "Locked")
            }
        }
    }
}

#Preview {
    StreaksView(stats: HabitStats())
}
