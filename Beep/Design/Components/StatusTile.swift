import SwiftUI

/// Home header tile. Content layer (secondary background), tappable.
struct StatusTile: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String
    var detail: LocalizedStringKey? = nil
    var tint: Color = .accentColor
    var isProminent = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.m + 2)
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isProminent ? AnyShapeStyle(tint.opacity(0.12)) : AnyShapeStyle(Color.cardBackground),
                    in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
        #if os(macOS)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(.separator))
        #endif
        .contentShape(.rect(cornerRadius: Theme.cardRadius))
    }
}
