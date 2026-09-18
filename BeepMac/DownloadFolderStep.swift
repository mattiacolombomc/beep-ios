import SwiftUI

/// Onboarding (Mac only): where course folders go. Suggests ~/Desktop or ~/Documents,
/// like WeBeep Sync did, but any folder works.
struct DownloadFolderStep: View {
    let next: () -> Void
    @Environment(DownloadFolder.self) private var folder
    @State private var picking = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(spacing: Theme.Spacing.s) {
                Text("Where should your courses go?").font(.title2.weight(.semibold))
                Text("Beep creates one folder per course and keeps it up to date. Pick an empty folder, for example “WeBeep” on your Desktop.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.l)
            if let url = folder.url {
                Label(url.path(percentEncoded: false).abbreviatingHome, systemImage: "folder.fill")
                    .font(.callout.monospaced())
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, Theme.Spacing.l)
            }
            if let error = folder.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            Spacer()
            VStack(spacing: Theme.Spacing.s) {
                if folder.isChosen {
                    Button {
                        picking = true
                    } label: {
                        Text("Choose Another Folder…").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                } else {
                    Button {
                        picking = true
                    } label: {
                        Text("Choose Folder…").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
                if folder.isChosen {
                    Button(action: next) {
                        Text("Continue").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .navigationTitle("Download folder")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { folder.choose(url) }
        }
        .fileDialogDefaultDirectory(URL.userHome.appending(path: "Desktop"))
    }
}

extension URL {
    /// The real home folder. Inside the sandbox `homeDirectory` points at the app container.
    static var userHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return .homeDirectory
    }
}

extension String {
    /// "/Users/name/Desktop/WeBeep" → "~/Desktop/WeBeep".
    var abbreviatingHome: String {
        let home = URL.userHome.path(percentEncoded: false)
        let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        return hasPrefix(trimmedHome) ? "~" + dropFirst(trimmedHome.count) : self
    }
}
