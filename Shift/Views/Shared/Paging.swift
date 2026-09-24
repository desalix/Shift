//
//  Paging.swift
//  Shift
//

import SwiftUI

/// Pages laid side by side in a horizontal paging scroll view, for the month
/// and day screens.
///
/// The neighbouring pages are real, already-built views, so a drag pulls the
/// next month (or day) in under the finger and lets go with the system's own
/// momentum and snapping — rather than a slide played after the swipe ends.
/// The stack is lazy, so only the pages on or next to the screen exist.
///
/// Pages are addressed by an integer index; the caller maps it to a month or a
/// day. Changing `index` from outside (the toolbar arrows, another tab) scrolls
/// to it; scrolling updates `index`.
struct Pager<Page: View>: View {
    let range: Range<Int>
    @Binding var index: Int
    @ViewBuilder let page: (Int) -> Page

    /// The scroll view's own record of the visible page. Seeded with `index`
    /// so the first frame already shows the right page.
    @State private var position: Int?

    init(range: Range<Int>, index: Binding<Int>, @ViewBuilder page: @escaping (Int) -> Page) {
        self.range = range
        _index = index
        self.page = page
        _position = State(initialValue: index.wrappedValue)
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(range, id: \.self) { pageIndex in
                    page(pageIndex)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position)
        .onChange(of: position) { _, newValue in
            if let newValue, newValue != index { index = newValue }
        }
        .onChange(of: index) { _, newValue in
            guard newValue != position else { return }
            withAnimation(.snappy(duration: 0.3)) { position = newValue }
        }
    }
}

/// A `Pager` over months, bound to the month on screen. Home and Income both
/// use it, so the two scroll the same way.
struct MonthPager<Page: View>: View {
    @Binding var month: Date
    @ViewBuilder let page: (Date) -> Page

    @Environment(\.calendar) private var calendar

    var body: some View {
        Pager(
            range: CalendarMath.pageableMonths,
            index: Binding(
                get: { CalendarMath.monthIndex(of: month, calendar: calendar) },
                set: { month = CalendarMath.month(atIndex: $0, calendar: calendar) }
            )
        ) { index in
            page(CalendarMath.month(atIndex: index, calendar: calendar))
        }
    }
}
