//
//  OnboardingView.swift
//  Shift
//

import SwiftUI

/// First-run setup. Work and personal calendar entries are always available;
/// the only real choice here is whether to turn on the School section, which
/// unlocks subjects, exams, and assignments throughout the app.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var wantsSchool = false

    var body: some View {
        @Bindable var settings = settings

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    Text("What will you use Shift for?")
                        .font(.title3.weight(.semibold))

                    Text("Work and personal entries are always available. Turn on School if you also track classes, exams, and assignments.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    UseCaseRow(
                        symbol: EventType.work.symbolName,
                        color: settings.workColor.color,
                        title: String(localized: "Work"),
                        subtitle: String(localized: "Shifts with hourly or fixed pay"),
                        isOn: .constant(true),
                        isLocked: true
                    )

                    UseCaseRow(
                        symbol: EventType.calendar.symbolName,
                        color: settings.calendarColor.color,
                        title: String(localized: "Personal calendar"),
                        subtitle: String(localized: "Everything else in your day"),
                        isOn: .constant(true),
                        isLocked: true
                    )

                    UseCaseRow(
                        symbol: EventType.school.symbolName,
                        color: settings.schoolColor.color,
                        title: String(localized: "School"),
                        subtitle: String(localized: "Subjects, exams, and assignments"),
                        isOn: $wantsSchool,
                        isLocked: false
                    )
                }

                Text("You can change this at any time in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    settings.schoolEnabled = wantsSchool
                    settings.hasCompletedOnboarding = true
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(settings.accentColor.color)
                .symbolRenderingMode(.hierarchical)

            Text("Welcome to Shift")
                .font(.largeTitle.weight(.bold))

            Text("A calendar built for changing schedules and changing pay.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }
}

private struct UseCaseRow: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isLocked {
                // Always-on rows show a checkmark rather than a disabled toggle:
                // a greyed-out switch reads as "unavailable", not "included".
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Always included"))
            } else {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .accessibilityLabel(Text(title))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
