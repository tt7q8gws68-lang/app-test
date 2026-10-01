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

    var icon: AppIcon.Name {
        switch self {
        case .assignment: .notes
        case .exam: .badge
        case .quiz: .assignments
        case .project: .plan
        case .reading: .courses
        }
    }
}
