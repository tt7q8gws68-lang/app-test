import SwiftData
import SwiftUI

@Model
final class Course {
    var name: String
    var colorToken: CourseColor
    var sortIndex: Int

    @Relationship(deleteRule: .nullify, inverse: \Assignment.course)
    var assignments: [Assignment] = []

    init(name: String, color: CourseColor, sortIndex: Int) {
        self.name = name
        self.colorToken = color
        self.sortIndex = sortIndex
    }

    var color: Color { colorToken.color }
}
