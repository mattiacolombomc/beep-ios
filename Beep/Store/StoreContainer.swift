import Foundation
import SwiftData

enum StoreContainer {
    static let schema = Schema([Course.self, CourseSection.self, CourseModule.self, FileItem.self, WebeepNotification.self])

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
