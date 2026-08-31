//
//  NavigationBars.swift
//  Shift
//

import SwiftUI

/// Bottom navigation for compact width (iPhone portrait).
struct BottomTabBar: View {
    @Binding var selection: AppTab
    let tabs: [AppTab]

    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 20))
                            .symbolVariant(selection == tab ? .fill : .none)
                        Text(tab.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    .foregroundStyle(selection == tab ? settings.accentColor.color : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Left navigation for regular width (iPad landscape).
///
/// `fixedSize(horizontal:)` is what pins the rail to the width of its widest
/// label, per the spec — the stack reports its ideal width and the parent
/// `HStack` gives the remaining space to the content panel.
struct SideNavBar: View {
    @Binding var selection: AppTab
    let tabs: [AppTab]

    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 16))
                            .symbolVariant(selection == tab ? .fill : .none)
                            // A fixed icon column keeps the labels aligned
                            // regardless of each glyph's natural width.
                            .frame(width: 22, alignment: .center)
                        Text(tab.title)
                            .font(.callout)
                            .lineLimit(1)
                            .fixedSize()
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 10)
                    .foregroundStyle(selection == tab ? settings.accentColor.color : Color.primary)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(settings.accentColor.color.opacity(0.14))
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .fixedSize(horizontal: true, vertical: false)
        .background(.bar)
        .overlay(alignment: .trailing) { Divider() }
    }
}
