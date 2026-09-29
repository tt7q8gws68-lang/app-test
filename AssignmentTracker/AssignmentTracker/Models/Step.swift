import Foundation
import SwiftData

@Model
final class Step {
    var title: String
    var isDone: Bool
    var sortIndex: Int
    var assignment: Assignment?

    init(title: String, isDone: Bool = false, sortIndex: Int) {
        self.title = title
        self.isDone = isDone
        self.sortIndex = sortIndex
    }
}
