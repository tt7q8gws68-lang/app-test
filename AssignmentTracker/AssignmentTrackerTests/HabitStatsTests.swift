import Foundation
import SwiftData
import Testing
@testable import AssignmentTracker

struct HabitStatsTests {
    let calendar = Fixtures.calendar
    /// Tue Sep 29, 2026, 10:00.
    let now = Fixtures.today

    private func day(_ offset: Int, _ hour: Int = 23, _ minute: Int = 59) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.date(byAdding: .day, value: offset, to: start)!)!
    }

    /// Created well ahead, due `due` days from today, finished `finished` (nil = not yet).
    private func record(due: Int, finished: Date?) -> CompletionRecord {
        CompletionRecord(dueDate: day(due), createdAt: day(-60), completedAt: finished)
    }

    private func stats(_ records: [CompletionRecord]) -> HabitStats {
        HabitStats(records: records, now: now, calendar: calendar)
    }

    @Test func countsOnTimeCompletionsInARow() {
        let result = stats([
            record(due: -5, finished: day(-6, 12)),
            record(due: -3, finished: day(-3, 20)),
            record(due: -1, finished: day(-2, 9)),
        ])
        #expect(result.currentStreak == 3)
        #expect(result.bestStreak == 3)
    }

    @Test func lateCompletionResetsTheStreak() {
        let result = stats([
            record(due: -6, finished: day(-7)),
            record(due: -5, finished: day(-6)),
            record(due: -4, finished: day(-3)), // a day late
            record(due: -1, finished: day(-1, 12)),
        ])
        #expect(result.currentStreak == 1)
        #expect(result.bestStreak == 2)
    }

    @Test func overdueWorkBreaksTheStreak() {
        let result = stats([
            record(due: -3, finished: day(-3, 12)),
            record(due: -1, finished: nil),
        ])
        #expect(result.currentStreak == 0)
        #expect(result.bestStreak == 1)
    }

    @Test func openWorkNotYetDueDoesNotBreakTheStreak() {
        let result = stats([
            record(due: -2, finished: day(-2, 12)),
            record(due: 0, finished: nil), // due tonight
            record(due: 4, finished: nil),
        ])
        #expect(result.currentStreak == 1)
    }

    @Test func finishingEarlyCountsNow() {
        let result = stats([
            record(due: -2, finished: day(-2, 12)),
            record(due: 5, finished: day(0, 9)),
        ])
        #expect(result.currentStreak == 2)
        #expect(result.earlyFinishes == 1)
    }

    @Test func workAddedAfterItWasDueIsIgnored() {
        // Past syllabus items are imported already done: neither a win nor a loss.
        let imported = CompletionRecord(dueDate: day(-10), createdAt: day(0, 9), completedAt: day(0, 9))
        let missedImport = CompletionRecord(dueDate: day(-8), createdAt: day(0, 9), completedAt: nil)
        let result = stats([record(due: -1, finished: day(-1, 8)), imported, missedImport])
        #expect(result.currentStreak == 1)
        #expect(result.totalOnTime == 1)
    }

    @Test func onTimeRateCoversTheLast30Days() {
        let result = stats([
            record(due: -40, finished: nil), // too old to count
            record(due: -10, finished: day(-10, 12)),
            record(due: -5, finished: day(-4)),
            record(due: -2, finished: day(-2, 12)),
            record(due: -1, finished: day(-1, 12)),
        ])
        #expect(result.onTimeRate == 0.75)
        #expect(stats([]).onTimeRate == nil)
        // Finished early counts; open work not yet due doesn't.
        #expect(stats([record(due: 3, finished: day(0, 9)), record(due: 4, finished: nil)]).onTimeRate == 1)
    }

    @Test func perfectWeeksNeedEverythingOnTime() {
        // Today is Tue Sep 29; last week ran Mon Sep 21 – Sun Sep 27.
        let result = stats([
            record(due: -8, finished: day(-8, 12)), // Mon Sep 21
            record(due: -3, finished: day(-4)),     // Sat Sep 26
            record(due: -15, finished: day(-15, 12)), // week of Sep 14
            record(due: -12, finished: nil),          // same week, missed
            record(due: 0, finished: day(0, 9)),      // this week: not over yet
        ])
        #expect(result.perfectWeeks == 1)
    }

    @Test func todayProgress() {
        let result = stats([
            record(due: 0, finished: day(0, 8)),
            record(due: 0, finished: nil),
            record(due: 1, finished: nil),
        ])
        #expect(result.dueToday == 2)
        #expect(result.openToday == 1)
        #expect(!result.allDoneToday)
    }

    @Test func activityIsKeyedByCompletionDay() {
        let result = stats([
            record(due: 3, finished: day(-1, 14)),
            record(due: 4, finished: day(-1, 16)),
            record(due: -2, finished: day(-1)), // late: not counted
        ])
        #expect(result.activity == [calendar.startOfDay(for: day(-1)): 2])
    }

    @Test func badgesUnlockFromBestStreak() {
        let records = (1...5).map { record(due: -$0, finished: day(-$0 - 1)) }
        let unlocked = Set(stats(records).badges.filter(\.isUnlocked).map(\.id))
        #expect(unlocked.isSuperset(of: ["first", "streak3", "streak5", "early"]))
        #expect(!unlocked.contains("streak10"))
    }

    @Test func badgeProgressAndPicks() {
        // Best streak 1, nothing else: Off the Mark earned, Hat Trick at 1 / 3 is next.
        let result = stats([record(due: -1, finished: day(-1, 12))])
        let hatTrick = result.badges.first { $0.id == "streak3" }!
        #expect(hatTrick.current == 1 && hatTrick.goal == 3)
        #expect(result.mostRecentEarned?.id == "first")
        #expect(result.nextToEarn?.id == "streak3")
    }

    @Test func noBadgesEarnedYet() {
        let result = stats([])
        #expect(result.mostRecentEarned == nil)
        #expect(result.nextToEarn?.id == "first")
    }

    @Test func mostRecentIsTheHighestTier() {
        // 5 in a row, all a day early: first, streak3, streak5 and early are unlocked.
        let records = (1...5).map { record(due: -$0, finished: day(-$0 - 1)) }
        #expect(stats(records).mostRecentEarned?.id == "early")
    }

    @Test func weekStripMarksOnTimeEmptyAndFutureDays() {
        // Today is Tue Sep 29; the week runs Mon Sep 28 – Sun Oct 4.
        let result = stats([
            record(due: 2, finished: day(0, 9)),  // finished today, on time
            record(due: -1, finished: day(-1, 12)), // finished Monday
        ])
        let week = result.weekDays(now: now, calendar: calendar)
        #expect(week.count == 7)
        #expect(week.map(\.kind) == [.onTime, .onTime, .future, .future, .future, .future, .future])
        #expect(week.map(\.isToday) == [false, true, false, false, false, false, false])
        #expect(result.onTimeThisWeek(now: now, calendar: calendar) == 2)
        #expect(stats([]).weekDays(now: now, calendar: calendar).first?.kind == .empty)
    }

    @Test func celebratesBadgesMilestonesAndFinishingTheDay() {
        let two = stats([record(due: -2, finished: day(-3)), record(due: -1, finished: day(-2))])
        let three = stats([record(due: -2, finished: day(-3)), record(due: -1, finished: day(-2)), record(due: 0, finished: day(0, 9))])
        #expect(three.celebration(since: two)?.title == "Badge unlocked: Hat Trick")

        var before = HabitStats()
        before.dueToday = 2
        before.openToday = 1
        var after = before
        after.openToday = 0
        #expect(after.celebration(since: before)?.title == "All done for today")
        #expect(after.celebration(since: after) == nil)
    }
}

struct SampleDataSeedingTests {
    @Test @MainActor func seedsOnlyOnceEvenAfterEverythingIsDeleted() throws {
        let defaults = UserDefaults(suiteName: "SampleDataSeedingTests")!
        defaults.removePersistentDomain(forName: "SampleDataSeedingTests")
        let container = try ModelContainer(for: ModelContainer.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext

        SampleData.seedIfNeeded(context, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<Course>()) == 4)

        try context.fetch(FetchDescriptor<Assignment>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<Course>()).forEach(context.delete)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Course>()) == 0)
        SampleData.seedIfNeeded(context, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<Course>()) == 0)
    }
}

struct ZipArchiveRobustnessTests {
    @Test func emptyDeflatedEntryIsAnErrorNotACrash() throws {
        // A one-entry ZIP whose deflated entry claims 10 bytes but carries none.
        var zip = Data()
        func u16(_ v: UInt16) { zip.append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)]) }
        func u32(_ v: UInt32) { (0..<4).forEach { zip.append(UInt8((v >> (8 * $0)) & 0xFF)) } }
        let name = Array("word/document.xml".utf8)
        u32(0x0403_4B50); u16(20); u16(0); u16(8); u16(0); u16(0); u32(0); u32(0); u32(10); u16(UInt16(name.count)); u16(0)
        zip.append(contentsOf: name)
        let central = UInt32(zip.count)
        u32(0x0201_4B50); u16(20); u16(20); u16(0); u16(8); u16(0); u16(0); u32(0); u32(0); u32(10)
        u16(UInt16(name.count)); u16(0); u16(0); u16(0); u16(0); u32(0); u32(0)
        zip.append(contentsOf: name)
        let size = UInt32(zip.count) - central
        u32(0x0605_4B50); u16(0); u16(0); u16(1); u16(1); u32(size); u32(central); u16(0)

        let archive = try ZipArchive(data: zip)
        #expect(throws: ZipArchive.ZipError.corrupt) { try archive.contents(of: "word/document.xml") }
    }
}

struct CourseColorTests {
    @Test func everyColorHasADistinctName() {
        #expect(CourseColor.allCases.count == 12)
        #expect(Set(CourseColor.allCases.map(\.name)).count == 12)
    }

    @Test func existingStoredColorsStillDecode() throws {
        for raw in ["blue", "orange", "purple", "teal"] {
            let decoded = try JSONDecoder().decode(CourseColor.self, from: Data("\"\(raw)\"".utf8))
            #expect(decoded.rawValue == raw)
        }
    }
}
