// Generates the sample syllabi in SampleSyllabi/ used for manual testing of syllabus import.
// Run from the repository root:  swift Tools/make_sample_syllabi.swift
//
// - ECON220_Econometrics_Syllabus.pdf   text-based PDF (week-by-week schedule)
// - MACRO210_Macroeconomics_Scan.pdf    image-only "scanned" PDF (table schedule), for OCR
// - MACRO210_Macroeconomics_Photo.jpg   the same page as a photo, for the photo import path
// The .docx, .txt and broken samples are written by Tools/make_docx_sample.py.

import AppKit
import CoreGraphics
import Foundation

let outputDirectory = URL(fileURLWithPath: "SampleSyllabi", isDirectory: true)
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let pageSize = CGSize(width: 612, height: 792) // US Letter
let margin: CGFloat = 54

enum Row {
    case title(String)
    case subtitle(String)
    case heading(String)
    case text(String)
    case columns([String], widths: [CGFloat], bold: Bool = false)
    case gap
}

func font(for row: Row) -> NSFont {
    switch row {
    case .title: .boldSystemFont(ofSize: 18)
    case .subtitle: .systemFont(ofSize: 11)
    case .heading: .boldSystemFont(ofSize: 12)
    case .columns(_, _, let bold): bold ? .boldSystemFont(ofSize: 10) : .systemFont(ofSize: 10)
    default: .systemFont(ofSize: 10.5)
    }
}

/// Draws rows top to bottom, starting new pages as needed.
func draw(_ rows: [Row], in context: CGContext, beginPage: () -> Void, endPage: () -> Void) {
    var y = pageSize.height - margin
    beginPage()
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = graphics

    func put(_ string: String, x: CGFloat, width: CGFloat, font: NSFont) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.black])
        let bounds = attributed.boundingRect(with: CGSize(width: width, height: 1000), options: [.usesLineFragmentOrigin])
        attributed.draw(with: CGRect(x: x, y: y - bounds.height, width: width, height: bounds.height), options: [.usesLineFragmentOrigin])
        return ceil(bounds.height)
    }

    for row in rows {
        if y < margin + 40 {
            endPage(); beginPage(); y = pageSize.height - margin
            NSGraphicsContext.current = graphics
        }
        let contentWidth = pageSize.width - margin * 2
        switch row {
        case .gap:
            y -= 10
        case .title(let s), .subtitle(let s), .heading(let s), .text(let s):
            if case .heading = row { y -= 6 }
            y -= put(s, x: margin, width: contentWidth, font: font(for: row)) + 3
        case .columns(let cells, let widths, _):
            var x = margin
            var height: CGFloat = 0
            for (cell, width) in zip(cells, widths) {
                height = max(height, put(cell, x: x, width: width - 8, font: font(for: row)))
                x += width
            }
            y -= height + 4
        }
    }
    endPage()
}

func makePDF(_ rows: [Row], to url: URL) {
    var box = CGRect(origin: .zero, size: pageSize)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    draw(rows, in: context, beginPage: { context.beginPDFPage(nil) }, endPage: { context.endPDFPage() })
    context.closePDF()
}

/// Renders rows as a slightly rotated, grainy 200-dpi page image, like a phone scan.
func makeScanImage(_ rows: [Row]) -> CGImage {
    let scale: CGFloat = 200 / 72
    let width = Int(pageSize.width * scale), height = Int(pageSize.height * scale)
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(CGColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1)) // off-white paper
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    context.rotate(by: 0.8 * .pi / 180)
    context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
    context.scaleBy(x: scale, y: scale)
    draw(rows, in: context, beginPage: {}, endPage: {})

    // Speckle noise.
    context.scaleBy(x: 1 / scale, y: 1 / scale)
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<9000 {
        let gray = CGFloat.random(in: 0.55...0.85, using: &generator)
        context.setFillColor(CGColor(gray: gray, alpha: 0.35))
        context.fill(CGRect(x: .random(in: 0..<CGFloat(width), using: &generator),
                            y: .random(in: 0..<CGFloat(height), using: &generator), width: 2, height: 2))
    }
    return context.makeImage()!
}

// MARK: - ECON 220 (text PDF, week-by-week)

let econ: [Row] = [
    .title("ECON 220: Introduction to Econometrics"),
    .subtitle("Fall 2026 · Tue/Thu 10:00–11:15 AM · Dr. Lena Okafor · okafor@university.edu"),
    .gap,
    .text("Classes begin Monday, August 31, 2026. All problem sets are submitted on Canvas by 11:59 PM on the due date."),
    .heading("Grading"),
    .columns(["Problem Sets (5)", "25%"], widths: [260, 80]),
    .columns(["Quizzes (2)", "10%"], widths: [260, 80]),
    .columns(["Midterm Exam", "20%"], widths: [260, 80]),
    .columns(["Empirical Project", "20%"], widths: [260, 80]),
    .columns(["Final Exam", "25%"], widths: [260, 80]),
    .heading("Policies"),
    .text("Late policy: problem sets lose 10% per day late. Office hours: Wed 2–4 PM, Room 310."),
    .heading("Weekly Schedule"),
    .text("Week 1: Review of probability and statistics"),
    .text("Week 2: Simple linear regression"),
    .text("    Thu: Read Chapter 4"),
    .text("Week 3: Least squares assumptions"),
    .text("    Fri: Problem Set 1 due"),
    .text("Week 4: Hypothesis tests"),
    .text("    Thu: Quiz 1"),
    .text("Week 5: Multiple regression"),
    .text("    Fri: Problem Set 2 due"),
    .text("Week 6: Nonlinear regression functions"),
    .text("Week 7: Midterm Exam — Thursday, October 15, 10:00 AM"),
    .text("Week 8: Panel data. Problem Set 3 due Oct 23"),
    .text("Week 9: Binary dependent variables"),
    .text("    Tue: Quiz 2"),
    .text("Week 10: Instrumental variables. Empirical project proposal due Nov 2–6"),
    .text("Week 11: Experiments. Problem Set 4 due Friday, Nov 13"),
    .text("Week 12: Guest lecture reflection due — date TBA"),
    .text("Week 13: Time series. Problem Set 5 due Nov 30"),
    .text("Week 14: Empirical project paper due Dec 4 at 5 PM"),
    .gap,
    .text("Final Exam: Friday, December 11, 9:00 AM – 12:00 PM, Hall B"),
]
makePDF(econ, to: outputDirectory.appendingPathComponent("ECON220_Econometrics_Syllabus.pdf"))

// MARK: - MACRO 210 (scanned table)

let macroWidths: [CGFloat] = [70, 220, 210]
let macro: [Row] = [
    .title("MACRO 210 — Intermediate Macroeconomics"),
    .subtitle("Fall 2026 · Prof. Daniel Reyes · MWF 1:00 PM"),
    .gap,
    .heading("Schedule of Assessments"),
    .columns(["Date", "Topic", "Due"], widths: macroWidths, bold: true),
    .columns(["Sep 30", "Growth accounting", "Problem Set 2 (5%)"], widths: macroWidths),
    .columns(["Oct 1", "Solow model", "Quiz 3"], widths: macroWidths),
    .columns(["Oct 9", "Consumption", "Problem Set 3 (5%)"], widths: macroWidths),
    .columns(["Oct 16", "Review", "Midterm Exam (25%), 1:00 PM"], widths: macroWidths),
    .columns(["Oct 26", "Fall break", "No class"], widths: macroWidths),
    .columns(["Nov 6", "Monetary policy", "Policy Brief (10%)"], widths: macroWidths),
    .columns(["Nov 20", "Open economy", "Quiz 4"], widths: macroWidths),
    .columns(["Dec 4", "Wrap-up", "Research Paper (20%)"], widths: macroWidths),
    .columns(["Dec 14", "Finals week", "Final Exam (30%), 9:00 AM"], widths: macroWidths),
]
let scan = makeScanImage(macro)

let scanURL = outputDirectory.appendingPathComponent("MACRO210_Macroeconomics_Scan.pdf")
var box = CGRect(origin: .zero, size: pageSize)
let scanContext = CGContext(scanURL as CFURL, mediaBox: &box, nil)!
scanContext.beginPDFPage(nil)
scanContext.draw(scan, in: box)
scanContext.endPDFPage()
scanContext.closePDF()

let photo = NSBitmapImageRep(cgImage: scan)
try! photo.representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
    .write(to: outputDirectory.appendingPathComponent("MACRO210_Macroeconomics_Photo.jpg"))

// MARK: - PSYC 101 (text PDF, wrapped multi-column table + date headings)
// 24 graded items. The table's long cells wrap onto several lines, and names like
// "Discussion Post" and "Worksheet" aren't the usual "assignment" keywords.

let psycWidths: [CGFloat] = [34, 64, 200, 206]
let psyc: [Row] = [
    .title("PSYC 101: Introduction to Psychology"),
    .subtitle("Fall 2026 · Tue/Thu 2:00–3:15 PM · Dr. Maya Patel"),
    .text("The semester starts on Monday, August 31, 2026. Weekly discussion posts are due on Canvas by 11:59 PM."),
    .heading("Course Calendar"),
    .columns(["Wk", "Date", "Topic & Readings", "Assignments Due"], widths: psycWidths, bold: true),
    .columns(["1", "Tue 9/1", "Introduction; the science of psychology (Ch. 1)", "Syllabus acknowledgment"], widths: psycWidths),
    .columns(["2", "Tue 9/8", "Research methods and ethics in human subjects research (Ch. 2)", "Discussion Post 1; Worksheet 1: Designing a study"], widths: psycWidths),
    .columns(["3", "Thu 9/17", "Biological bases of behavior (Ch. 3)", "Reading Check 1"], widths: psycWidths),
    .columns(["4", "Tue 9/22", "Sensation and perception (Ch. 4)", "Discussion Post 2"], widths: psycWidths),
    .columns(["5", "Thu 10/1", "States of consciousness (Ch. 5)", "Worksheet 2: Sleep diary analysis"], widths: psycWidths),
    .columns(["6", "Tue 10/6", "Learning: classical and operant conditioning (Ch. 6)", "Discussion Post 3"], widths: psycWidths),
    .columns(["7", "Thu 10/15", "Exam 1 (Chapters 1–6), in class", ""], widths: psycWidths),
    .columns(["8", "Tue 10/20", "Memory (Ch. 7)", "Journal Entry 1: Memory experiment reflection"], widths: psycWidths),
    .columns(["9", "Thu 10/29", "Cognition, language and intelligence (Ch. 8)", "Reading Check 2; Research Paper Milestone 1: Topic"], widths: psycWidths),
    .columns(["10", "Tue 11/3", "Development across the lifespan (Ch. 9)", "Discussion Post 4"], widths: psycWidths),
    .columns(["11", "Thu 11/12", "Motivation and emotion (Ch. 10)", "Worksheet 3: Emotion regulation strategies"], widths: psycWidths),
    .columns(["12", "Tue 11/17", "Personality (Ch. 11)", "Exam 2 (Chapters 7–11)"], widths: psycWidths),
    .columns(["13", "Tue 11/24", "Social psychology (Ch. 12)", "Journal Entry 2"], widths: psycWidths),
    .columns(["14", "Thu 12/3", "Psychological disorders and therapy (Ch. 13–14)", "Research Paper Milestone 2: Annotated bibliography"], widths: psycWidths),
    .gap,
    .heading("Other Key Dates"),
    .text("Friday, October 9"),
    .text("  •  Lab participation form (SONA credits, part 1)"),
    .text("Monday, November 30"),
    .text("  •  Poster draft for peer review"),
    .text("  •  Extra credit article summary"),
    .text("Wednesday, December 9"),
    .text("  •  Final research paper, 11:59 PM"),
    .text("Tuesday, December 15"),
    .text("  •  Cumulative final exam, 10:30 AM, Room 120"),
]
makePDF(psyc, to: outputDirectory.appendingPathComponent("PSYC101_Psychology_Syllabus.pdf"))

print("Wrote samples to \(outputDirectory.path)")
