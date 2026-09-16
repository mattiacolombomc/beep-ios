import SwiftUI

struct CourseRow: View {
    let course: Course

    private var subtitle: String {
        [course.code, course.professors].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.m - 4) {
            CourseTile(monogram: course.monogram, color: course.color)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(course.title)
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
