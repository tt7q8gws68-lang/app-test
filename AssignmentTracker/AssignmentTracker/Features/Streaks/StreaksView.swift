import SwiftUI

/// Motivation: the on-time streak and stats, this week's progress, and badges to unlock.
struct StreaksView: View {
    let stats: HabitStats

    @State private var isShowingInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ScreenHeader(subtitle: "Best streak: \(stats.bestStreak)", title: "Streaks") {
                        GlassCircleButton(icon: .info, label: "How streaks work") {
                            isShowingInfo = true
                        }
                    }

                    StreakCard(stats: stats)
                    ThisWeekCard(stats: stats)
                    BadgesSummary(stats: stats)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { DuskBackground() }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingInfo) { StreakInfoSheet() }
        }
    }
}

// MARK: - Streak card

private struct StreakCard: View {
    let stats: HabitStats

    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 44

    private var message: String {
        if stats.allDoneToday { return "Everything due today is done." }
        if stats.openToday > 0 { return "\(stats.openToday) due today. Keep it going." }
        if stats.currentStreak == 0 { return "Finish your next assignment on time to start one." }
        return "Keep finishing before the deadline."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                TintTile(content: .icon(.streaks), color: Palette.streakOrange, size: 60, cornerRadius: 20)
                    // A quick hop when the streak changes (symbolEffect only animates SF Symbols).
                    .keyframeAnimator(initialValue: 1.0, trigger: stats.currentStreak) { tile, scale in
                        tile.scaleEffect(scale)
                    } keyframes: { _ in
                        SpringKeyframe(1.18, duration: 0.15)
                        SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(stats.currentStreak)")
                            .font(.system(size: numberSize, weight: .bold))
                            .tracking(-1.5)
                            .contentTransition(.numericText())
                        Text("on time in a row")
                            .font(.body.weight(.semibold))
                    }
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)

            Rectangle().fill(Palette.hairline).frame(height: 1)

            HStack(alignment: .top, spacing: 12) {
                Stat(
                    value: stats.onTimeRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
                    label: "On time (30d)"
                )
                Stat(value: "\(stats.perfectWeeks)", label: "Perfect weeks")
                Stat(value: "\(stats.earlyFinishes)", label: "Done early")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 28)
        .animation(.snappy, value: stats.currentStreak)
    }
}

private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .contentTransition(.numericText())
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - This week

private struct ThisWeekCard: View {
    let stats: HabitStats

    var body: some View {
        let days = stats.weekDays()
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.body.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(stats.onTimeThisWeek()) on time")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryText)
            }
            HStack(spacing: 6) {
                ForEach(days, id: \.date) { DayColumn(day: $0) }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .glassCard(cornerRadius: 26)
    }
}

private struct DayColumn: View {
    let day: WeekDayStatus

    var body: some View {
        VStack(spacing: 6) {
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption.weight(day.isToday ? .bold : .medium))
                .foregroundStyle(day.isToday ? Palette.accentText : Palette.secondaryText)
            circle
                .frame(width: 34, height: 34)
                .overlay {
                    // A ring 2pt outside the circle, drawn without changing the layout.
                    if day.isToday {
                        Circle().strokeBorder(Palette.accentText, lineWidth: 2).padding(-4)
                    }
                }
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide)) + (day.isToday ? ", today" : ""))
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var circle: some View {
        switch day.kind {
        case .onTime:
            Circle()
                .fill(Palette.onTimeGreen)
                .overlay {
                    AppIcon(.check, size: 14, weight: 3)
                        .foregroundStyle(Palette.onAccent)
                }
        case .empty:
            Circle().fill(Palette.faintFill)
        case .future:
            Circle()
                .strokeBorder(Palette.dashedOutline, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                .padding(2)
        }
    }

    private var accessibilityValue: String {
        switch day.kind {
        case .onTime: "Finished on time"
        case .empty: "Nothing finished"
        case .future: "Upcoming"
        }
    }
}

// MARK: - Badges

private struct BadgesSummary: View {
    let stats: HabitStats

    var body: some View {
        let earned = stats.badges.filter(\.isUnlocked).count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader("Badges")
                Spacer()
                NavigationLink {
                    BadgesView(stats: stats)
                } label: {
                    Text("\(earned) of \(stats.badges.count) · See all")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accentText)
                        .frame(minHeight: 44)
                }
                .padding(.trailing, 4)
            }

            GlassGroup {
                if let recent = stats.mostRecentEarned {
                    BadgeRow(badge: recent)
                }
                if stats.mostRecentEarned != nil, stats.nextToEarn != nil {
                    InsetDivider()
                }
                if let next = stats.nextToEarn {
                    BadgeRow(badge: next)
                }
            }
        }
    }
}

/// A badge as a list row: earned ones say so, locked ones show progress.
struct BadgeRow: View {
    let badge: Badge

    var body: some View {
        HStack(alignment: badge.isUnlocked ? .center : .top, spacing: 14) {
            TintTile(
                content: .icon(badge.isUnlocked ? badge.icon : .locked),
                color: badge.isUnlocked ? Palette.streakOrange : Palette.completedText
            )
            if badge.isUnlocked {
                VStack(alignment: .leading, spacing: 3) {
                    Text(badge.title)
                        .font(.body.weight(.semibold))
                    Text(badge.detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Earned")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(badge.title)
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text("\(min(badge.current, badge.goal)) / \(badge.goal)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.secondaryText)
                            .monospacedDigit()
                    }
                    ThinProgressBar(fraction: badge.fraction, tint: Palette.streakOrange)
                    Text(badge.detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(badge.isUnlocked ? "Earned" : "\(min(badge.current, badge.goal)) of \(badge.goal)")
    }
}

#Preview {
    StreaksView(stats: HabitStats())
}
