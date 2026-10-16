import SwiftUI

struct CourseRow: View {
    let course: Course

    var body: some View {
        HStack(spacing: Theme.Spacing.m - 4) {
            CourseTile(monogram: course.monogram, color: course.color)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(course.title)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                CourseMetaLine(course: course)
            }
            Spacer(minLength: Theme.Spacing.s)
            HStack(spacing: Theme.Spacing.s) {
                if course.newFilesCount > 0 {
                    Text("\(course.newFilesCount)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor, in: .capsule)
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(course.newFilesCount) new files")
                }
                if course.syncEnabled {
                    Image(systemName: "arrow.down.circle")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Auto-download on")
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(Rectangle())
    }
}

/// Year, code and professors, each with its own weight: the year as a small tag in the course
/// colour (it tells two editions apart), the code in fixed-width digits, the professors as text.
struct CourseMetaLine: View {
    let course: Course

    var body: some View {
        HStack(spacing: Theme.Spacing.s - 2) {
            if course.isAcademicYear {
                Text(course.categoryName)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(course.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(course.color.opacity(0.14), in: .capsule)
            }
            if let code = course.code {
                Text(code)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            if let profs = course.professors {
                Text(profs)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .truncationMode(.tail)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
