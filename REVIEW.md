# AssignmentTracker: code-quality review (static)

**Scope:** `AssignmentTracker/AssignmentTracker/` (iOS 26, Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI + SwiftData). All paths below are relative to that folder.
**Method:** Five reviewers produced candidate findings. A sixth pass then checked each one against the code. Line numbers were corrected, duplicates merged and false positives dropped, and cross-module issues were added. **Nothing was built, run or tested.** Every item marked "needs Xcode" is unverified until someone builds it and runs the test suite in Xcode.

## Summary

The codebase is in good shape overall. Most logic is pure and `nonisolated` so it can be tested, models and views are kept apart, and the comments explain the reasoning. The review found:

- **One clear, cheaply fixed bug (B1).** A replaced celebration toast gets cleared early.
- **A few real behaviour bugs in syllabus import (B2, B3).** These need a product or UX decision before fixing.
- **One possible crash (B5).** Deleting from the detail screen may crash. This needs Xcode to confirm.
- **Several cross-module issues (X1–X7).** These are mostly inconsistencies rather than defects:
  - three different definitions of "this week";
  - an injected clock that is used in some places and ignored in others;
  - Models that depend on SwiftUI and the design system;
  - persistence that relies entirely on autosave;
  - one regex-heavy `normalized()` called inside nested loops.
- **Few safe edits.** Only a small set can be applied safely without a build. They are listed in the Fix plan.

Severity: **High** = data loss or crash likely · **Med** = user-visible wrong behaviour · **Low** = edge case, clarity or minor cost.

## Ranked table

Ranked by impact against the risk of fixing it. "Preserves?" means the proposed fix keeps current behaviour. "C/S/P?" means the fix touches concurrency, state or persistence.

| ID | Sev | File:line | Issue | Fix | Preserves? | C/S/P? | Xcode? | Class |
|---|---|---|---|---|---|---|---|---|
| B1 | Med | Features/Root/RootView.swift:84-88 | When a new celebration replaces the old one, the old task is cancelled. `try? await Task.sleep` swallows the cancellation and then sets `celebration = nil`, which clears the **new** toast at once. | Add `guard !Task.isCancelled else { return }` after the sleep. The sibling task at :80-81 already does this. | Only in the buggy path | State | No | B |
| B2 | Med | Services/SyllabusImport/ImportCandidate.swift:82-91; Features/Import/SyllabusImportModel.swift:24-26 | `reresolve` does not recompute `duplicateOf`. With no date, a candidate counts as a duplicate when its title matches anything in the class (:114). After the term start is set, it keeps the stale duplicate flag and stays unchecked under "Already in this class", even when the match is on another day. A candidate going from dated to undated also stays `isIncluded` (harmless to save, but it shows a checked circle). | Call `refreshDuplicates()` after `reresolve` in the `termStart` didSet, and un-include candidates that lose their date. | No | State | Yes (tests) | C |
| B3 | Med | Features/Import/ImportReviewView.swift:91-92, 140-151; CandidateEditorSheet.swift:128-132 | "Add Item" creates a candidate with `isIncluded = true` and a due date. Only the Cancel button discards a blank one. Swiping the sheet down leaves an included "Untitled" row, which saves as an assignment titled "Assignment" (SyllabusImportModel.swift:201). | Use `.interactiveDismissDisabled(original.title.isEmpty)`, or remove blank new candidates on dismiss. This is a UX decision. | No | State | Yes | C |
| B5 | Med? | Features/Detail/AssignmentDetailView.swift:86-89 | `dismiss()` then `assignment.delete(from:)`. During the pop animation the body (and `@Bindable`) may read a deleted `@Model`, and SwiftData can trap on detached backing data. | Verify on device. If it reproduces, delete after the pop finishes, or have the parent delete it. | No | Persistence | **Yes** | C |
| B4 | Low-Med | Services/SampleData.swift:10-17 | The one-shot flag is set **before** the work. `(try? fetchCount) ?? 0` treats a fetch failure as "empty", so sample data can be inserted into a real user store. | `guard let count = try? context.fetchCount(...), count == 0 else { return }` | Happy path yes; only the failure path changes | Persistence | No | B |
| B6 | Low-Med | Services/SyllabusImport/FoundationModelSyllabusParser.swift:124-139, 82-110 | A single line longer than `chunkSize` becomes its own chunk. `halve` splits it into `[line, ""]`, so it can never shrink. After depth 2 it fails and is dropped silently. Chunk failures are only counted (:70-77), and the analyzer replaces the error with a reason string (SyllabusAnalyzer.swift:56-58). Nothing is logged. | Split overlong lines by characters or sentences. Add `os.Logger` diagnostics. | No | No | Yes | C |
| B7 | Low | Services/SyllabusImport/SyllabusDateResolver.swift:95-100 | The "Time range in syllabus" review flag can never fire. `timeRange` requires a trailing am/pm, and `twelveHourTime` then always matches the end of the range, so `time` is non-nil. | Check `timeRange` without the `time == nil` condition. Product decision: more items will be flagged. | No | No | Yes (tests) | C |
| B8 | Low | Features/Import/ImportReviewView.swift:31, 267; ImportCandidate.swift:46 | The review grouping uses `candidate.isPast()` (real `.now`, `Calendar.current`). The model's counts and save use `referenceDate`/`calendar` (SyllabusImportModel.swift:55, 65, 211). If these disagree (for example a sheet left open across midnight), the "Already passed" section and the "N past items" footnote can differ. | Expose `model.isPast(_:)` (or make `referenceDate`/`calendar` `private(set)`) and use it in `group(of:)`. | Yes except the midnight edge | State | No | B |
| B9 | Low | Models/DueBucket.swift:50-85 | `dueRowLabel(now:)` takes an injected `now` but uses `isDateInYesterday` (real clock). `dueDayLabel`/`plannedLabel` use `isDateInToday/Tomorrow` and ignore `now`. Call sites at AssignmentRow.swift:54, AssignmentDetailView.swift:137 and AssignToCourseSheet.swift:52 don't pass the environment's `currentTime`. | Derive yesterday, today and tomorrow from `now` via `calendar.isDate(_:inSameDayAs:)`, and thread `now` through. | No (tests use fixture dates) | No | Yes (tests) | C |
| B10 | Low | Features/Import/SyllabusImportModel.swift:136-137 | The comment "Set without triggering re-resolution" is false. The `termStart` didSet (:24-26) fires and re-resolves the **previous** candidates before they are overwritten. This is harmless in practice because candidates are empty after `startOver()`. | Correct the comment (or build candidates first). | Yes (comment only) | No | No | A |
| B11 | Low | SyllabusImportModel.swift:219-224; AssignmentEditorSheet.swift:206-213; ReminderScheduler.swift:40 | Fire-and-forget `Task`. The `requestAuthorization()` Bool is ignored, and the `center.add` error is ignored. Syncing while denied is harmless because add is a no-op, but there is no feedback. | Centralise in one `ReminderScheduler.schedule(_:)` that checks the status and logs errors. | No | Concurrency | Yes | C |
| B12 | Low | Features/Import/SyllabusImportSheet.swift:102-104 | `try? loadTransferable` drops photos silently (for example iCloud download failures). If all of them fail, the user sees "photos couldn't be opened" with no cause. | Count failures and surface "N photos couldn't be loaded". | No | No | Yes | C |
| B13 | Low | Features/Import/DocumentScanner.swift:34-36 | `didFailWithError` reports `onFinish([])`, which looks the same as cancel, so camera errors are invisible. | Pass an error case and show it. | No | No | Yes | C |
| B14 | Low (UX) | Features/List/AssignmentRow.swift:96-98 | The context-menu Delete is immediate and can't be undone. The detail screen asks for confirmation (AssignmentDetailView.swift:81-92). | Confirmation or undo. Product decision. | No | Persistence | Yes | C |
| B15 | Low | DesignSystem/FlowLayout.swift:19-25, 40 | Subviews are measured with `.unspecified` and placed at that size, so a chip wider than the container (a long course name) overflows instead of truncating. Each subview is measured 2-3 times per pass. | Clamp the proposal to `maxWidth`, and use the layout cache. Visual change. | No | No | Yes | C |
| B16 | Low | Models/HabitStats.swift:104 | "A day early" uses `24 * 3600`, which is off by an hour across DST. | `calendar.date(byAdding: .day, value: -1, to:)`. | No | No | Yes (tests) | C |
| B17 | Low | FoundationModelSyllabusParser.swift:146-149, 168-174 | The hallucination filter uses substring `contains` on normalized words ("set" matches "settings"). It also normalizes the whole chunk **per item**. | Match on word sets, and normalize the source once. Behaviour change. | No | No | Yes (tests) | C |
| X1 | Med (consistency) | WeekHeroSummary.swift:39-44; HabitStats.swift:124-125, 172-173; SyllabusDateResolver.swift:169-171; RuleBasedSyllabusParser.swift:139-144 vs CalendarView.swift:91, WeeksAheadList.swift:24 vs DueBucket.swift:34-48 | **Three meanings of "this week"**: (a) Monday–Sunday is hard-coded 5×; (b) the locale's `firstWeekday` (Sunday in en_US) in Calendar month and week views; (c) a rolling `WeekWindow` of today plus 6 days for the list buckets and hero ring. In en_US the hero strip and Calendar "This week" show different days. | Decide the product rule. Separately, extract the duplicated Monday-week code into one `nonisolated` helper (see Fix plan). | Helper yes / rule no | No | Helper: no | B (helper) / C (rule) |
| X2 | Med (consistency) | RootView.swift:24-27, 94 vs ImportReviewView.swift:31, 267; CandidateEditorSheet.swift:187-191; AssignmentRow.swift:86-87; AssignToCourseSheet.swift:52; PlanCard.swift:10, 34, 78; CalendarView.swift:85, 175-176, 235; WeeksAheadList.swift:9, 62, 107 | **Clock and calendar source is inconsistent.** RootView carefully maintains `\.currentTime`, but many views still read `.now`/`Calendar.current` directly. Five views capture `Calendar.current` as a stored `let`, while sibling views (DayCell) read it on every access. Nothing uses `@Environment(\.calendar)`. | Adopt one rule: `\.currentTime` plus `@Environment(\.calendar)` in views, and injected `now`/`calendar` in models. | Mostly | State | Yes | C |
| X3 | Low-Med (perf) | RuleBasedSyllabusParser.swift:279-285 used at :107-112; SyllabusAnalyzer.swift:85-87, 103-105; ImportCandidate.swift:110-117 (via SyllabusImportModel.swift:175-186 on the main actor); FoundationModelSyllabusParser.swift:146-147, 170-173 | `normalized()` runs 3 regex `replacingOccurrences` calls, each compiling a pattern, and is called inside nested O(n·m) loops. | Hoist the per-collection keys out of the inner loops (Fix plan A4/A5). Precompiling the regexes is a separate step that needs profiling. | Hoisting yes | Main-actor caller for ImportCandidate | Profiling | A (hoists) / C (rest) |
| X4 | Low (layering) | Models/Assignment.swift:2, 52-55; Course.swift:2, 21; CourseColor.swift:1, 10-25; Priority.swift:1, 16-22 (uses `Palette`); AssignmentKind.swift:17-25 and HabitStats.swift:29, 211 (use `AppIcon.Name`); Services/AssignmentActions.swift:2, 8, 16 (`withAnimation`) | Models depend on SwiftUI and the DesignSystem, and a Service performs UI animation. This blocks a UI-free model layer and puts transactions in the wrong place. | Move color and icon mappings into DesignSystem extensions, and put `withAnimation` at the call sites. | Yes | State (animation) | Yes | C |
| X5 | Low-Med (persistence) | No `modelContext.save()` anywhere (grep). Writes at SyllabusImportModel.swift:193-226, AssignmentEditorSheet.swift:190-215, AssignmentActions.swift:21-24, StepsCard.swift:85-101, CourseEditorSheet.swift:121-152 | The app relies entirely on SwiftData autosave. A kill or crash shortly after a bulk import or delete can lose it. Writes are spread across views with no error path. | Explicit `try context.save()` (with error UI) after bulk import, deletes and editor saves. | No (adds a failure path) | Persistence | Yes | C |
| X6 | Low | AssignmentRow.swift:96-98, AssignmentDetailView.swift:86-89, CourseEditorSheet.swift:138-152, StepsCard.swift:96-101, ImportReviewView.swift:82-83 | Delete flows are inconsistent: confirm vs. no confirm, dismiss-then-delete, and an inline loop over `course.assignments`. There is no `Course.delete(withAssignments:from:)` helper next to `Assignment.delete(from:)`. | Add a `Course` delete helper in AssignmentActions.swift, snapshot the list first (`let toDelete = Array(course.assignments)`), and use it everywhere. | Yes | Persistence | Yes | C |
| X7 | Low | AssignmentTrackerApp.swift:6-15; SampleData.swift:6-32 | Store open, seed and migration all run inside a stored-property initializer with `fatalError`. One-shot UserDefaults flags are set before the work, and there is no `VersionedSchema`/migration plan (enums are stored directly, so CourseColor raw values must never change). | Recovery UI instead of `fatalError`. Set flags after success. Add `VersionedSchema` before the next model change. | No | Persistence | Yes | C |
| P1 | Low | Features/List/AssignmentsView.swift:144-148, 150-177 | Each body rebuilds the hero `Item` array (faulting `course`). `matchesSearch` trims `searchText` once **per assignment**. | Trim the query once in `sections` (A6). Leave the rest until profiled. | Yes (A6) | No | No | A (A6) / C |
| P2 | Low | Features/Calendar/WeeksAheadList.swift:34, 37 | The computed `overdue` (an O(n) filter) is evaluated twice per body. | `let overdue = overdue` at the top of `body`. | Yes | No | No | A |
| P3 | Low | Features/Streaks/StreaksView.swift:216-224 | `stats.mostRecentEarned`/`nextToEarn` are each evaluated twice, and each rebuilds the 8-element `badges` array. | Bind them to locals once. | Yes | No | No | A |
| P4 | Low | SyllabusTextExtractor.swift:223 (CharacterSet `.inverted` built per word); :182 vs :204 (`page.string` read twice per page) | Avoidable allocations in the PDF layout loop. | Hoist `.whitespacesAndNewlines.inverted` out of the loop (A). Passing the text in is an API change (C). | Yes | No | No | A / C |
| P5 | Low | Calendar views: MonthGridCard (CalendarView.swift:106-107), DayAgenda (:248-251), WeeksAheadList (:23-29, 8 × O(n)), DayLoadStrip (:111-113, 7 × O(items)); WeekHeroSummary.swift:43-49 (7 × O(n)); ImportReviewView.swift:54-58 (filter and sort ×5 per body); SyllabusImportModel.swift:50-73 (counts and a regex per candidate per body); `Assignment.tint` read in each DayCell | O(n) work per body in several places. Fine at student-scale data. | Group once per body if profiling shows a cost. | Yes | No | Profiling | C |
| P6 | Low | Features/Courses/CoursesView.swift:7, 32 | `@Query` of **all** assignments is used only to filter unassigned in memory; AssignToCourseSheet.swift:8 uses a predicate. However, this query may be what re-renders course summaries when assignments change. | Don't change it until Xcode confirms observation still works. | ? | State | **Yes** | C |
| P7 | Low | DesignSystem/DuskBackground.swift:17-21, 23-42 | The `glows` array is rebuilt on every init. Three blurs and a `drawingGroup` run per screen instance, and several are alive at once (tabs, sheets). | `private static let glows` (A). Blur cost needs Instruments, and changing it would change the look. | Yes / visual | No | Profiling | A / C |
| P8 | Low | Features/Root/RootView.swift:30-32, 69 | `records` (mapping every assignment) is recomputed on every RootView body for `onChange`. The `@State` bookkeeping (`lastStats` etc.) is written on each update. | Profile first. | ? | State | Profiling | C |
| P9 | Low | SyllabusTextExtractor.swift:138-157 (photos); DocumentScanner.swift:27 | All photos are decoded to 4000 px CGImages up front (about 64 MB each × up to 10) before OCR. Scan pages are converted on the main thread. | Decode lazily one image at a time inside the OCR loop. Move scan conversion off main. | Yes | Concurrency | Profiling | C |
| S1 | Low | Features/Import/ImportReviewView.swift:14, 28, 54 | `private enum Group` shadows `SwiftUI.Group` inside a SwiftUI view. | Rename to `ReviewGroup` (3 occurrences, file-private). | Yes | No | No | A |
| S2 | Low | Features/List/AssignmentsView.swift:14, 150, 168 | `private struct Section` shadows `SwiftUI.Section`. | Rename to `BucketSection` (3 occurrences). | Yes | No | No | A |
| S3 | Low | Models/DueBucket.swift:19-21 | `DueBucket.of(_ assignment:now:calendar:)` is unused in the app and in tests (grep). It is also the only non-`nonisolated` member. | Delete it. | Yes | No | No | A |
| S4 | Low | Services/SyllabusImport/ImportCandidate.swift:104 (+ :76, :88, SyllabusImportModel.swift:183) | The `resolver:` parameter of `defaultInclusion` is unused. No test calls it. | Remove the parameter and update the 3 call sites. | Yes | No | No | A |
| S5 | Low | Services/SyllabusImport/SyllabusDateResolver.swift:164-167 | A side effect (`reasons.append`) sits inside a `?? { … }()` closure. | Rewrite as `let weekday: Int; if let w = … { weekday = w } else { reasons.append(…); weekday = 6 }`. | Yes | No | No | A |
| S6 | Low | Services/SyllabusImport/SyllabusTextExtractor.swift:148-152 | The doc comment is split around `@concurrent`, so the second half sits between the attribute and `func`. | Put the whole doc comment above `@concurrent`. | Yes | No | No | A |
| S7 | Low | DesignSystem/GlassControls.swift:14; GlassCard.swift:19; ImportReviewView.swift:123; AssignmentDetailView.swift:162 | Raw `Color.white` contradicts Palette's "never raw colors" rule (Palette.swift:5). `Palette.onAccent` is not white in dark mode, so a separate token is needed. | Add `static let onAccentFill = Color.white` to Palette and use it in the 4 places. | Yes | No | No | A |
| S8 | Low | Features/List/AssignmentRow.swift:55 | `.accessibilityHidden(false)` is redundant. | Delete. | Yes | No | No | A |
| S9 | Low | DesignSystem/GlassControls.swift:87 vs :93 | `ProgressRing` clamps `fraction` for the trim but not for the gradient `endAngle`. | Compute `let clamped = min(max(fraction, 0), 1)` once and use it for both. Identical output for 0…1. | Yes (for 0…1) | No | No | A |
| S10 | Low | SyllabusTextExtractor.swift:130, 159 | The magic number `40` (minimum syllabus characters) appears twice, next to the named `minimumPageText`. | `private static let minimumSyllabusText = 40`. | Yes | No | No | A |
| S11 | Low | Features/Editor/CourseChips.swift:6 vs :19 | The doc says a "New Course" chip, but the UI says "New Class". App-wide the terms are mixed: "Courses" tab, "Add course" and editor `SectionHeader("Course")`, versus "New/Edit/Delete Class" and import "Class". | Fix the comment (A). The terminology is a product decision (C). | Yes | No | No | A / C |
| S12 | Low | Features/Import/CandidateEditorSheet.swift:83, 131, 139 vs 167 | `.whitespaces` is used for the Done/discard checks, but `.whitespacesAndNewlines` is used for save. A newline-only (pasted) title enables Done and then saves "". | Use `.whitespacesAndNewlines` in all three. Only newline-only input changes. | Edge only | No | No | A |
| S13 | Low | Features/Streaks/StreakInfoSheet.swift:7-13 | The `rules` array is rebuilt on every init. | `private static let rules`. | Yes | No | No | A |
| S14 | Low | Duplicated UI and logic: `isOverdue` (AssignmentRow.swift:14-16 / AssignmentDetailView.swift:132-134); near-identical complete buttons (AssignmentDetailView.swift:140-169); label-over-field cards, type-picker row and reminder toggle + "blocked" note (CandidateEditorSheet.swift / AssignmentEditorSheet.swift / ImportReviewView.swift:203-213); 23:59 default (AssignmentEditorSheet.swift:218-220, CandidateEditorSheet.swift:187-191, SyllabusImportModel.swift:144-147); `regex()`/match helpers (SyllabusDateResolver.swift:286-301 / RuleBasedSyllabusParser.swift:292-300); hairline `Rectangle` (StreaksView.swift:76, AssignmentsView.swift:216-219) vs `InsetDivider` | Copy-and-paste code. | Extract shared views and helpers. | Mostly | No | Yes | C |
| S15 | Low | RuleBasedSyllabusParser.parse :27-117 (~90 lines); ImportReviewView.body :35-152; SyllabusTextExtractor (errors + types + PDF + OCR + images + hashing); SyllabusImportModel (I/O + review editing + persistence) | Oversized units. | Split them up later, once there is build and test coverage. | Yes | State | Yes | C |
| S16 | Low | Magic numbers: InsetDivider leading 70/54/52/12 tied to tile sizes; `buttonArea = 58 + 4 + 16` (AssignmentDetailView.swift:95); TextLayout 0.45/0.75/1.5/0.9 | Unnamed layout constants that depend on each other. | Name the constants next to the tile sizes. | Yes | No | Yes | C |
| S17 | Low | Misc: `ChunkFailure` is reused for "all chunks failed" and "halve failed" (FoundationModelSyllabusParser.swift:44, 77, 94, 100); `termStart(in:)` method shadows the `termStart` property (SyllabusDateResolver.swift:30, 72, used in tests); `mostRecentEarned` actually returns the highest tier (HabitStats.swift:158-161, doc explains); many `internal` statics in Resolver/Parser/FM parser that tests use | Naming and access-control nits. | Leave as is, or rename together with the tests. | Yes | No | Yes (tests) | C |
| S18 | Low (a11y) | DesignSystem/GlassControls.swift:61-70 | `GlassSegmented` passes `EmptyView()` as the Picker label, so VoiceOver has no control name. | Add a `title` parameter and use `Text(title)` with `.labelsHidden()`. Changes VoiceOver output. | No | No | Yes | C |
| F1 | Med (risk) | Features/Root/DuskBackButton.swift:29-38 | A `@retroactive` extension overrides `viewDidLoad` and takes over the pop-gesture delegate for **every** `UINavigationController` in the process, including UIKit-presented ones such as the document camera and pickers. | Verify on device. Prefer a scoped `UIViewControllerRepresentable` hook. | No | No | **Yes** | C |
| F2 | Low | Services/ReminderScheduler.swift:5, 18-41 | A `nonisolated enum` reads `@Model Assignment`, which is main-actor-isolated by default. Every caller is on the main actor today, but the isolation contract is unclear and may only compile because of how SwiftData isolates models. | Mark `sync`/`cancel` `@MainActor` (or pass a Sendable snapshot). | Yes | **Concurrency** | **Yes** | C |
| F3 | Low | SyllabusTextExtractor.swift:78-95, 67, 120, 179-189 | When `fileSize` is unavailable the whole file is read before the size guard. If the `docxType` UTType lookup fails, it falls back to `.data`, which would accept every file. Plain text falls back to Latin-1 (UTF-16 files become mojibake). Scanned PDFs have no OCR page cap (up to 20 MB of pages). | Use `UTType(importedAs:)`/`.init(filenameExtension: "docx")`, add a page cap, and detect the encoding. | No | No | Yes | C |
| F4 | Info | Calendar force-unwraps: CalendarView.swift:22, 72, 92, 94-95, 143, 162, 239; WeeksAheadList.swift:24, 26-27, 51, 112; DueBucket.swift:41-42; HabitStats.swift:83, 107, 177; WeekHeroSummary.swift:44; PlanCard.swift:11; CandidateEditorSheet.swift:189-190; SampleData.swift:37-38; SyllabusImportModel.swift:144; SyllabusDateResolver.swift:245. Regex-group unwraps: SyllabusDateResolver.swift:195-218, 273-281; RuleBasedSyllabusParser.swift:159. `try!` on literal regexes: SyllabusDateResolver.swift:300, RuleBasedSyllabusParser.swift:299 | The Gregorian day/month arithmetic can't return nil in practice. The group unwraps are guaranteed by the patterns. The literal regexes are exercised by the tests. | No action. If a convention is wanted, use `?? fallback`, but don't mass-edit without a build. | Yes | No | — | C (no-op) |

### Dropped or downgraded after verification
- **HabitStats.swift:62 "stale onTimeRate comment":** the comment is accurate. `dueDate >= monthAgo` includes items that are due in the future and already finished, which matches "or finished early".
- **CourseEditorSheet.swift:138-152 "iterates a live relationship while deleting":** Swift's `for … in course.assignments` iterates an array copy, so this isn't a mutation-during-iteration bug. It was downgraded to the clarity and consistency item X6.
- **StepsCard.swift:96-101 "redundant removeAll before delete":** keep it. Removing the item explicitly inside `withAnimation` is what drives the row animation.
- **"Syncs reminders even if denied" (B11):** the effect is harmless because `UNUserNotificationCenter.add` does nothing when unauthorized. It was kept only as an observability issue.
- **SyllabusTextExtractor.swift:290-299 "thumbnail may upscale" and :244-260 "PDF /Rotate not applied":** probably false. ImageIO thumbnails don't upscale, and `PDFPage.draw(with:to:)` applies page rotation. Listed for Xcode verification only, with no fix proposed.
- **SyllabusImportSheet.swift:21 "throwaway model":** the `SyllabusImportModel.init` only stores values, so the cost is negligible. No action.
- **`ForEach(Array(x.enumerated()))` allocations** (AssignToCourseSheet.swift:24, CoursesView.swift:49, CalendarView.swift:125, WeeksAheadList.swift:40, AssignmentRow.swift:111): negligible at this scale. No action.
- **AppIcon `size`/`weight` var→let:** cosmetic. The explicit init already assigns them. Skipped.

## Bugs (behaviour changes needed)
- **B1** is the only bug safe to fix now: a one-line cancellation guard that mirrors the sibling task.
- **B2 and B3** are the import-review bugs users are most likely to hit. Both change behaviour and need test updates (`ImportCandidateTests`, `SyllabusImportModelTests`).
- **B5** may crash and needs Xcode to confirm.
- **B4** affects only the failure path. The guard keeps behaviour on the happy path.
- **B6, B7, B9, B16, B17** are correctness edge cases in parsing, labels and date maths. Each one changes output that tests check.
- **B11–B15** are UX or error-reporting gaps.

## Cross-module issues
- **X1, week definitions.** Three different meanings of "this week". The Monday-start logic is copied 5×, while the Calendar views follow the locale. This needs a product decision. A shared `nonisolated` helper is a safe first step.
- **X2, clock and calendar source.** There is one well-designed source of time (`\.currentTime`), but about 10 call sites bypass it. `Calendar.current` is captured in some views and read live in others. No view uses `@Environment(\.calendar)`.
- **X3, `normalized()`.** One regex-heavy function sits inside nested loops in 4 files, including a main-actor path (`refreshDuplicates` when the course changes).
- **X4, layering.** Models depend on SwiftUI, `Palette` and `AppIcon`, and a Service runs `withAnimation`.
- **X5, persistence.** No explicit saves anywhere. Writes are spread across views, with no error surface.
- **X6, deletion.** The delete flows are inconsistent and there is no Course delete helper.
- **X7, startup.** Opening the store, seeding and migration run in the App initializer with `fatalError`. Flags are set before the work, and there is no schema versioning.
- **Isolation conventions are inconsistent.** Value types are carefully marked `nonisolated` (DueBucket's static func, WeekWindow, CourseColor, Date extensions), but `DueBucket` itself, `Priority` (which reads `Palette`) and `ReminderScheduler` (F2) differ. **Any new shared helper must be declared `nonisolated`**, or the `nonisolated` parser and model code can't call it under default MainActor isolation.

## Performance
Nothing here is proven hot. The data is student-scale, and every non-trivial change needs Instruments. The safe micro-hoists (P1/A6, P2, P3, P4/A, P7/A, X3/A4–A5) remove repeated work without changing results. P5, P6, P8 and P9 need profiling. P6 must not be changed blindly.

## Structure and clarity
S1–S13 are safe local cleanups: renames, dead code, comments, constants and tokens. S14–S18 are duplication, size and naming issues that should wait for a build and test loop.

## Safety
F1 (a global UINavigationController override) and F2 (the isolation contract) need verification on a device or in Xcode. F3 covers input-hardening gaps in import. F4 needs no action.

## Fix plan

Criteria:
- **A and B** contain only edits that keep current behaviour (or change it only in a clearly buggy or failure path, flagged ¹). They must be local and unable to break compilation without a build: no new cross-file APIs except where noted, and no public signature used by tests.
- **B** additionally touches state, persistence or isolation, so it needs a careful reviewer.
- **C** must not be applied now.

### (A) Safe routine cleanup [Sonnet]
- **A1 = S1:** rename `ImportReviewView.Group` → `ReviewGroup` (lines 14, 28, 54).
- **A2 = S2:** rename `AssignmentsView.Section` → `BucketSection` (lines 14, 150, 168).
- **A3 = S3:** delete the unused `DueBucket.of(_ assignment:now:calendar:)` (DueBucket.swift:19-21).
- **A4 = X3 (part):** RuleBasedSyllabusParser.swift:107-112. Before the loop, precompute `let weighted = undated.filter { $0.weight != nil }.map { (normalized($0.title), $0.weight) }`, then look up the first match. It must preserve "first undated with a weight and the same normalized title".
- **A5 = X3 (part):** SyllabusAnalyzer.swift:85-87. Precompute `let ruleTitles = rules.map { RuleBasedSyllabusParser.normalized($0.title) }` and index into it. Keep the `titlesMatch` call (:103-105) as is.
- **A6 = P1:** AssignmentsView.swift:172-177. Trim `searchText` once in `sections` and pass the query to `matchesSearch`.
- **A7 = P2:** WeeksAheadList.swift. Add `let overdue = overdue` at the top of `body`.
- **A8 = P3:** StreaksView.swift:216-224. Bind `let recent = stats.mostRecentEarned, next = stats.nextToEarn` once.
- **A9 = P4 (part):** SyllabusTextExtractor.swift:223. Hoist `CharacterSet.whitespacesAndNewlines.inverted` (and `.whitespacesAndNewlines`) out of the per-word loop.
- **A10 = S5:** rewrite the `?? { … }()` side effect at SyllabusDateResolver.swift:164-167 as an explicit if/else, keeping the append order identical.
- **A11 = S6:** move the split doc comment above `@concurrent` (SyllabusTextExtractor.swift:148-152).
- **A12 = S10:** `private static let minimumSyllabusText = 40`, used at SyllabusTextExtractor.swift:130 and :159.
- **A13 = S7:** add `Palette.onAccentFill = Color.white` and replace the 4 raw `Color.white` uses.
- **A14 = S8:** remove the redundant `.accessibilityHidden(false)` (AssignmentRow.swift:55).
- **A15 = S9:** clamp `fraction` once in `ProgressRing` and use it for both the trim and `endAngle`.
- **A16 = S13 + P7 (part):** `private static let rules` in StreakInfoSheet and `private static let glows` in DuskBackground. Both are MainActor-isolated by default and only used from `body`.
- **A17 = S4:** remove the unused `resolver:` parameter of `ImportCandidateBuilder.defaultInclusion` and update the 3 call sites (none in tests).
- **A18 = B10 + S11 (comment):** correct the misleading comments at SyllabusImportModel.swift:136 and CourseChips.swift:6.
- **A19 = S12 ¹:** use `.whitespacesAndNewlines` in all three CandidateEditorSheet checks (newline-only input is the only change).

### (B) Safe, but touches concurrency, state or persistence [Opus]
- **B-1 = B1 ¹:** `guard !Task.isCancelled else { return }` after the sleep in `RootView .task(id: celebration)`.
- **B-2 = B4 ¹:** `SampleData.seedIfNeeded`: `guard let count = try? context.fetchCount(...), count == 0 else { return }`. Only a failed fetch changes behaviour (it no longer seeds). Keep the flag ordering as is, because that is a separate product decision.
- **B-3 = B8 ¹:** route `ImportReviewView.group(of:)` (and the "Set when classes start" default at :267) through the model's `referenceDate`/`calendar`, for example via a new `SyllabusImportModel.isPast(_:)` method. This is internal and not used by tests.
- **B-4 = X1 (helper only):** add one `nonisolated extension Calendar { func mondayWeekStart(for:) -> Date? }` and replace the 5 identical `mondayCalendar.firstWeekday = 2` blocks. It **must** be `nonisolated` because the callers are `nonisolated` structs. It must not change which calendar the Calendar-tab views use.

### (C) Do not apply now
| Items | Reason |
|---|---|
| B2, B3, B7, B9, B16, B17 | Behaviour or UX change; tests will need updating. Needs a product decision and a test run in Xcode. |
| B5, F1, F2, P6 | Possible crash, device-only behaviour, or SwiftData isolation and observation semantics. Needs verification in Xcode or on a device first. |
| B6, B11, B12, B13, B14, B15, F3, S18 | New error and UX surfaces (messages, logging, confirmation, layout, VoiceOver output). Product or UX decision. |
| X2, X4, X5, X6, X7 | Cross-cutting refactors across many files, involving persistence and environment plumbing. Too large to do without a build loop. |
| X1 (the rule), S11 (terminology) | Product decision about the definition of a week and the "Class" vs "Course" wording. |
| X3 (regex precompile, FM `detectedItem` / `ImportCandidate.duplicate` hoists), P1 (rest), P4 (API part), P5, P7 (blur), P8, P9 | Needs profiling. Some need API changes used by tests (`detectedItem(from:source:)`, `duplicate(of:in:calendar:)`, `layoutText(of:)`). |
| S14, S15, S16, S17 | Large or multi-file refactors, and renames of APIs used by tests. Wait for a build and test loop. |
| F4 | No action needed. |

¹ Changes behaviour only in a currently buggy, edge or failure path. It is called out so the reviewer can decide.

## Not reviewed / limits
- **Static review only.** Nothing was compiled, run, profiled or tested. Line numbers were checked against the working tree on 2026-10-08.
- **Not reviewed:**
  - the `AssignmentTrackerTests/` sources, which were only grepped to check API usage before A/B items;
  - `Tools/`, `design/` (HTML mockups) and `SampleSyllabi/`;
  - `Resources/Assets.xcassets`;
  - the Xcode project settings beyond isolation, Swift version and deployment target.
- `ZipArchive.swift`, `DocxTextReader.swift`, `SVGPath.swift`, `TextLayout.swift` (beyond its constants), `ScreenHeader`, `RowLabel`, `CheckCircle` and `SectionHeader` got only a surface pass. No candidate findings were raised against them.
