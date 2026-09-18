import SwiftUI

struct AcknowledgementsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                PersonCard(name: "Mattia Colombo", role: "Beep author", symbol: "person.crop.circle.fill", tint: .accentColor, links: [
                    .init(title: "mattiacolombo.com", symbol: "globe", url: URL(string: "https://mattiacolombo.com")!),
                    .init(title: "github.com/mattiacolombomc", symbol: "chevron.left.forwardslash.chevron.right", url: URL(string: "https://github.com/mattiacolombomc")!),
                    .init(title: "Beep on GitHub", symbol: "star", url: URL(string: "https://github.com/mattiacolombomc/beep-ios")!),
                ])
            } header: {
                Text("Made by")
            }
            Section {
                PersonCard(name: "Matteo Visotto", role: "myPoliFile · MIT License", symbol: "doc.text.fill", tint: Theme.coursePalette[1], links: [
                    .init(title: "github.com/matteovisotto/myPoliFile", symbol: "chevron.left.forwardslash.chevron.right", url: URL(string: "https://github.com/matteovisotto/myPoliFile")!),
                ], note: "Beep is inspired by and partly derived from myPoliFile, the first unofficial iOS client for WeBeep.")
                PersonCard(name: "Tommaso Morganti", role: "WeBeep Sync · GPL-3.0", symbol: "arrow.triangle.2.circlepath.circle.fill", tint: Theme.coursePalette[3], links: [
                    .init(title: "github.com/toto04/webeep-sync", symbol: "chevron.left.forwardslash.chevron.right", url: URL(string: "https://github.com/toto04/webeep-sync")!),
                ], note: "The login handshake with WeBeep follows the approach pioneered by WeBeep Sync for desktop.")
            } header: {
                Text("Thanks to")
            }
            Section {
                DisclosureGroup("MIT License – myPoliFile") {
                    Text(mitLicense)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Licenses")
            } footer: {
                Text("Beep is not affiliated with, endorsed by, or sponsored by Politecnico di Milano. WeBeep is a trademark of its owner.")
            }
        }
        .groupedList()
        .navigationTitle("Acknowledgements")
        .inlineNavigationTitle()
    }

    private var mitLicense: String {
        """
        Copyright (c) 2021 Matteo Visotto

        Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
        """
    }
}

private struct PersonCard: View {
    struct Link: Identifiable {
        let title: String
        let symbol: String
        let url: URL
        var id: URL { url }
    }

    let name: String
    let role: LocalizedStringKey
    let symbol: String
    let tint: Color
    let links: [Link]
    var note: LocalizedStringKey? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m - 4) {
            HStack(spacing: Theme.Spacing.m - 4) {
                Image(systemName: symbol)
                    .font(.title)
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.headline)
                    Text(role).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let note {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(links) { link in
                Button {
                    openURL(link.url)
                } label: {
                    Label(link.title, systemImage: link.symbol)
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .tint(tint)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
