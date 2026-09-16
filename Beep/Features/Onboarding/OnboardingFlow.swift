import SwiftData
import SwiftUI

/// After the first login: index everything, pick auto-download courses, ask for notifications.
struct OnboardingFlow: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @AppStorage("onboarding.done") private var onboardingDone = false
    @State private var step = 0
    @State private var indexed = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: FirstSyncStep(indexed: $indexed) { step = 1 }
                case 1: CourseSelectionStep { step = 2 }
                default: NotificationsStep { finish() }
                }
            }
            .animation(.snappy, value: step)
        }
        .task { await runFirstSync() }
    }

    private func runFirstSync() async {
        guard !indexed, let client = session.client, let user = session.user else { indexed = true; return }
        _ = await sync.syncAll(client: client, userID: user.id, trigger: .launch)
        indexed = true
    }

    private func finish() {
        onboardingDone = true
        if let client = session.client, let user = session.user {
            Task { _ = await sync.syncAll(client: client, userID: user.id, trigger: .manual) }
        }
    }
}

private struct FirstSyncStep: View {
    @Environment(SyncEngine.self) private var sync
    @Binding var indexed: Bool
    let next: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            ZStack {
                Circle().stroke(Color(.secondarySystemBackground), lineWidth: 10).frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: indexed ? 1 : fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 120, height: 120)
                    .animation(.linear(duration: 0.3), value: fraction)
                Image(systemName: indexed ? "checkmark" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            VStack(spacing: Theme.Spacing.s) {
                Text(indexed ? "Your courses are ready" : "Reading your WeBeep courses…")
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    .multilineTextAlignment(.center)
            }
            Spacer()
            Button(action: next) {
                Text("Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!indexed)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .navigationTitle("Welcome")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var fraction: Double {
        if case .indexing(let done, let total, _) = sync.phase, total > 0 { return Double(done) / Double(total) }
        return 0
    }
    private var detail: String {
        if case .indexing(let done, let total, let current) = sync.phase {
            return [String(localized: "\(done) of \(total) courses"), current].compactMap { $0 }.joined(separator: "\n")
        }
        if indexed, let r = sync.lastReport { return String(localized: "\(r.coursesIndexed) courses indexed") }
        return String(localized: "Only the index is downloaded now; files come next.")
    }
}

private struct CourseSelectionStep: View {
    let next: () -> Void
    @Query(sort: \Course.title) private var courses: [Course]

    private var enabledCount: Int { courses.filter(\.syncEnabled).count }
    private var currentYear: [Course] { courses.filter { $0.isCurrentYear && !$0.isHidden && !$0.isArchived } }

    var body: some View {
        SyncCoursesView()
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Theme.Spacing.s) {
                    Text(enabledCount == 0
                         ? "Nothing downloads automatically. Pick courses now or later in Settings."
                         : "\(enabledCount) courses will download new files automatically.")
                        .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                        .multilineTextAlignment(.center)
                    if enabledCount == 0, !currentYear.isEmpty {
                        Button {
                            for c in currentYear { c.syncEnabled = true }
                        } label: {
                            Text("Enable \(currentYear.count) courses of this year").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                    Button(action: next) {
                        Text(enabledCount == 0 ? "Skip for now" : "Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
                .background(.bar)
            }
            .navigationTitle("Auto-download")
    }
}

private struct NotificationsStep: View {
    let finish: () -> Void
    @AppStorage("settings.notifications") private var notifications = true
    @AppStorage("settings.backgroundRefresh") private var backgroundRefresh = true

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(spacing: Theme.Spacing.s) {
                Text("Know when new material lands").font(.title2.weight(.semibold))
                Text("Beep checks WeBeep in the background and tells you when professors upload something. No spam: one notification per check.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.l)
            Spacer()
            VStack(spacing: Theme.Spacing.s) {
                Button {
                    Task {
                        notifications = await Notifier.requestPermission()
                        backgroundRefresh = true
                        finish()
                    }
                } label: {
                    Text("Allow notifications").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                Button {
                    notifications = false
                    finish()
                } label: {
                    Text("Not now").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}
