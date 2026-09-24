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
/// momentum and snapping.
///
/// Only a window of pages exists: the one on screen and `buffer` either side,
/// built eagerly so a swipe never waits for a page to be made. When a swipe
/// settles, the window re-centres — the far page is dropped and the next one
/// beyond is built — while nothing is moving. A lazy stack would instead build
/// each page just as it slid into view, which is what made swiping hitch.
///
/// Pages are addressed by an integer index; the caller maps it to a month or a
/// day. `index` is updated when a swipe settles, not during it, so the rest of
/// the screen doesn't redraw mid-swipe. Changing `index` from outside (the
/// toolbar arrows, another tab) scrolls to it.
struct Pager<Page: View>: View {
    let range: Range<Int>
    @Binding var index: Int
    @ViewBuilder let page: (Int) -> Page

    /// Pages kept built on each side of the one on screen.
    static var buffer: Int { 3 }

    @State private var scroll: ScrollPosition
    /// The page the window is built around.
    @State private var center: Int
    @State private var isOnScreen = false

    init(range: Range<Int>, index: Binding<Int>, @ViewBuilder page: @escaping (Int) -> Page) {
        self.range = range
        _index = index
        self.page = page
        _scroll = State(initialValue: ScrollPosition(id: index.wrappedValue))
        _center = State(initialValue: index.wrappedValue)
    }

    var body: some View {
        // Pages are sized from the space between the bars, measured out here.
        // Sizing them from the scroll view instead made them full-screen: a
        // scroll view reaches under the navigation and tab bars, so the top
        // and bottom of every page were hidden behind them.
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(PagerWindow.pages(around: center, buffer: Self.buffer, in: range), id: \.self) { pageIndex in
                        page(pageIndex)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition($scroll)
        }
        .onScrollPhaseChange { _, phase in
            guard phase == .idle, let settled = scroll.viewID(type: Int.self) else { return }
            if settled != index { index = settled }
            recenter(on: settled)
        }
        .onChange(of: index) { _, newValue in
            guard newValue != scroll.viewID(type: Int.self) else { return }
            if isOnScreen, abs(newValue - center) <= Self.buffer {
                // The arrows: the page is already built, so slide to it.
                withAnimation(.snappy(duration: 0.3)) { scroll.scrollTo(id: newValue) }
            } else {
                // Off screen (the other tab moved) or far away: jump, and
                // build the window around the new page.
                recenter(on: newValue)
            }
        }
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }

    /// Moves the window so `page` is in its middle, keeping it on screen.
    private func recenter(on page: Int) {
        guard page != center else { return }
        center = page
        scroll.scrollTo(id: page)
    }
}

/// Which pages a `Pager` keeps built.
enum PagerWindow {
    /// `center` and up to `buffer` pages either side, clipped to `range`.
    static func pages(around center: Int, buffer: Int, in range: Range<Int>) -> [Int] {
        guard !range.isEmpty else { return [] }
        let clamped = min(max(center, range.lowerBound), range.upperBound - 1)
        let lower = max(range.lowerBound, clamped - buffer)
        let upper = min(range.upperBound - 1, clamped + buffer)
        return Array(lower ... upper)
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
