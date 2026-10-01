# Assignment Tracker

A SwiftUI app for iOS 26 and later that tracks class assignments. It uses Liquid Glass and SwiftData, and follows the system light/dark setting. The HTML mockups it's built from are in `design/`.

Open `AssignmentTracker/AssignmentTracker.xcodeproj` in Xcode 26 or later and run the **AssignmentTracker** scheme. On first launch the app adds the sample courses and assignments from the mockups.

## Features

The app has four tabs: **Assignments**, **Calendar**, **Courses** and **Streaks**.

- **Assignments:** weekly progress, an All / To do / Done filter, groups (Overdue, Today, This week, Later, Earlier), check-off, and search (pull down). The 🔥 chip shows your streak and opens the Streaks tab. Long-press a row for Plan to Work On.
- **Detail:** due date, priority and grade weight, type badge, a steps checklist, notes, and mark complete. Edit and Delete are in the ⋯ menu.
- **New / Edit sheet:** title, course, due date and time, a reminder the day before (a local notification), priority, and notes.
- **Syllabus import:** tap the document button at the top right of the Assignments list.
- **Calendar:**
  - **Month:** a grid with course-colored dots for what's due and a ring for planned work. Tap a day to see what's due and what's planned.
  - **Weeks:** the next 8 weeks, with a load bar for each day and busy weeks (5 or more due, or an exam) flagged.
- **Courses:** every class in one grouped list, with its initials, the next thing due and how many are open. Tap one to rename it, pick from 12 colors, or delete it (with or without its assignments). If any assignments have no class, **Assign** lets you choose one for each. Classes can also be created from the New Assignment sheet or during syllabus import.
- **Plan to work on:** pick a day to do an assignment (on the detail screen, or long-press a row). It appears on that day in the Calendar.
- **Streaks:** (the ⓘ button explains how it's counted)
  - **On time in a row:** grows when you finish before the due time, and resets on late or overdue work. Work added after it was due, like past syllabus items, doesn't count.
  - **Also shown:** best streak, on-time rate for the last 30 days, perfect weeks, done early, this week day by day, and your latest and next badge (See all shows all 8).
  - **Celebrations:** a toast with haptics when you finish everything due today, reach a streak milestone, or unlock a badge.

## Syllabus import

1. **Pick the class.** You can also add a new one.
2. **Pick the syllabus:**
   - a file: PDF, Word `.docx`, plain text or RTF, up to 20 MB
   - photos from the library
   - a scan with the document camera (only on devices with a camera)
3. **Review what was found.** Nothing is saved yet. Items are grouped into:
   - **Check these dates:** a date was found but is uncertain, such as a range ("Nov 2–6" uses the last day), a week with no day ("Week 5" uses Friday), or a weekday that doesn't match the date.
   - **Ready to add**
   - **Needs a date:** the syllabus said TBA or gave no date. These are left out until you set one.
   - **Already passed or in this class:** past items and duplicates. These are unchecked by default.

   On this screen you can:
   - Tap a row to edit its title, type, date, weight or notes.
   - Long-press a row to delete it.
   - Use **Add Item** for anything that was missed.
   - Change **Classes start** to re-place every "Week N" date.
4. **Add.** Checked items become normal assignments in the chosen class. Their priority comes from the item type and weight (exams and items worth 20% or more are High). Items whose due date has already passed are included by default and added as done, so the class record is complete. Use **Skip All** on that group to leave them out.

Importing the same file into the same class again shows a warning, and items already in the class are skipped.

### How it works

| Stage | Implementation |
|---|---|
| Text extraction | `SyllabusTextExtractor`: PDFKit for PDFs; pages with no text layer (scans) are rendered and read with on-device Vision text recognition. `TextLayout` rebuilds each page from positioned text (PDF word boxes or OCR boxes) so schedule tables survive: columns are split with " \| " and wrapped cells are joined back to their row. `.docx` is read with a small ZIP reader (`ZipArchive`, using Apple's Compression framework) and `XMLParser`. |
| Item detection | `SyllabusAnalyzer` uses Apple's **on-device Foundation Models** (guided generation into typed Swift structs) when Apple Intelligence is available, and always cross-checks with `RuleBasedSyllabusParser`. The rules parser reads tables cell by cell, carries date headings down to the bullets under them, and knows common item names. Items found by either one are kept. A model chunk that fails is split and retried, or skipped, without losing the other chunks. When the model isn't available, the rules parser runs alone and the review screen says so. |
| Dates | `SyllabusDateResolver` handles explicit dates, times, ranges, weekdays, "Week N, Friday" relative to the semester start, and years that aren't written. The model only copies date text as written; all date calculation is in this tested code. |
| Review state | `ImportCandidate` and `ImportCandidateBuilder` (duplicates, default inclusion, re-placing dates when the start date changes) and `SyllabusImportModel` (the view model). |

**Why on-device and not a cloud LLM:** the syllabus never leaves the phone, and there's no API key, backend, network dependency or per-use cost. The on-device model is available because the minimum version is iOS 26. The rule-based fallback covers devices without Apple Intelligence.

## Tests

```bash
xcodebuild test -project AssignmentTracker/AssignmentTracker.xcodeproj -scheme AssignmentTracker -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The Swift Testing suites in `AssignmentTrackerTests/` cover date resolution, the rule-based parser, table layout rebuilding, DOCX/ZIP reading, PDF and OCR extraction on the sample files, merging model and rule results, the review and save logic, and streaks and badges.

## Sample syllabi

`SampleSyllabi/` contains test files. Regenerate them with `swift Tools/make_sample_syllabi.swift` and `python3 Tools/make_docx_sample.py`.

| File | Covers |
|---|---|
| `ECON220_Econometrics_Syllabus.pdf` | Text PDF with a week-by-week schedule, a stated start date, a range, TBA, and a grading breakdown |
| `PSYC101_Psychology_Syllabus.pdf` | 21 items: a schedule table with wrapped cells and several items per cell, plus date headings with bullets |
| `MACRO210_Macroeconomics_Scan.pdf` | Image-only, slightly rotated "scan" of a schedule table (OCR) |
| `MACRO210_Macroeconomics_Photo.jpg` | The same page as a photo |
| `MoneyBanking_Syllabus.docx` | Word table, including a weekday that doesn't match its date |
| `Seminar_NoDates.txt` | Graded work with no dates |
| `Broken_Syllabus.pdf` | Not a real PDF, for the error path |

To test the fallback on a device that has Apple Intelligence, add `-SyllabusDetector rules` as a launch argument (Debug builds only).
