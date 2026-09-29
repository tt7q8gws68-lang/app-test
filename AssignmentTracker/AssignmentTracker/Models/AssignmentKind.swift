import Foundation

nonisolated enum AssignmentKind: String, Codable, CaseIterable, Identifiable {
    case assignment, exam, quiz, project, reading

    var id: Self { self }

    var label: String {
        switch self {
        case .assignment: "Assignment"
        case .exam: "Exam"
        case .quiz: "Quiz"
        case .project: "Project"
        case .reading: "Reading"
        }
    }

    var systemImage: String {
        switch self {
        case .assignment: "doc.text"
        case .exam: "graduationcap"
        case .quiz: "checklist"
        case .project: "folder"
        case .reading: "book"
        }
    }
}
