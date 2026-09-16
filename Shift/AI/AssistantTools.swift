//
//  AssistantTools.swift
//  Shift
//

import Foundation

/// The tool surface exposed to the model, plus the decoding of its calls.
///
/// Every tool *proposes* a change rather than performing one. The model has no
/// path to the store: it emits structured arguments, this file turns them into
/// `AssistantAction` values, and the UI applies them only after the user agrees.
enum AssistantTools {
    static let createEvents = "create_events"
    static let deleteEvent = "delete_event"
    static let rescheduleEvent = "reschedule_event"
    static let createSubject = "create_subject"
    static let enableSchool = "enable_school"

    /// Local wall-clock, no offset. The model is told the user's time zone in
    /// the system prompt and works entirely in local time, which avoids a whole
    /// class of off-by-one-day errors around midnight and DST.
    static let dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

    static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = dateFormat
        return formatter
    }

    /// JSON Schema definitions sent with every request.
    static func definitions() -> [[String: Any]] {
        let eventProperties: [String: Any] = [
            "title": [
                "type": "string",
                "description": "Short name for the entry. For a school exam this may be omitted.",
            ],
            "type": [
                "type": "string",
                "enum": ["work", "school", "calendar"],
                "description": "work = a paid shift, school = exam/assignment/other, calendar = anything else.",
            ],
            "start": [
                "type": "string",
                "description": "Local start, formatted \(dateFormat). No time zone offset.",
            ],
            "end": [
                "type": "string",
                "description": "Local end, formatted \(dateFormat). Must be after start.",
            ],
            "address": ["type": "string", "description": "Optional location."],
            "compensation_type": [
                "type": "string",
                "enum": ["hourly", "fixed"],
                "description": "Optional, work only. Omit when the user does not track pay for this shift.",
            ],
            "rate_cents": [
                "type": "integer",
                "description": "Optional, work only. Integer cents: 1250 means 12.50 euros. Interpreted per hour when compensation_type is hourly, otherwise as the total. Omit when pay is not tracked.",
            ],
            "school_kind": [
                "type": "string",
                "enum": ["exam", "assignment", "other"],
                "description": "Required when type is school.",
            ],
            "subject_name": [
                "type": "string",
                "description": "Required when type is school. Must match an existing subject, or be created first with create_subject.",
            ],
            "notes": [
                "type": "string",
                "description": "Optional, maximum 250 characters.",
            ],
        ]

        return [
            [
                "name": createEvents,
                "description": """
                Propose one or more calendar entries. Always expand a repeating request into \
                explicit individual entries — one object per occurrence — applying any skip \
                rules (alternate weeks, public holidays) yourself. Never emit a recurrence rule.
                """,
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "events": [
                            "type": "array",
                            "description": "One object per entry to create.",
                            "items": [
                                "type": "object",
                                "properties": eventProperties,
                                "required": ["title", "type", "start", "end"],
                            ],
                        ]
                    ],
                    "required": ["events"],
                ],
            ],
            [
                "name": deleteEvent,
                "description": "Propose deleting one existing entry, identified by the id shown in the context.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "The entry's UUID."],
                        "reason": ["type": "string", "description": "Short reason, shown to the user."],
                    ],
                    "required": ["id"],
                ],
            ],
            [
                "name": rescheduleEvent,
                "description": "Propose moving one existing entry to a new time.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "The entry's UUID."],
                        "start": ["type": "string", "description": "New local start, formatted \(dateFormat)."],
                        "end": ["type": "string", "description": "New local end, formatted \(dateFormat)."],
                    ],
                    "required": ["id", "start", "end"],
                ],
            ],
            [
                "name": createSubject,
                "description": "Propose creating a school subject. Use before creating a school entry for a subject that does not exist yet.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "The subject name."]
                    ],
                    "required": ["name"],
                ],
            ],
            [
                "name": enableSchool,
                "description": "Propose turning on the School section. Use when the user asks for something school-related while School is disabled.",
                "input_schema": [
                    "type": "object",
                    "properties": [:] as [String: Any],
                ],
            ],
        ]
    }

    /// Turns one decoded tool call into actions, dropping anything malformed.
    ///
    /// A model that emits a bad date or an unknown enum should degrade to
    /// "nothing proposed" rather than to a corrupt entry, so parsing failures
    /// here are silent by design and surface as an empty proposal.
    static func actions(
        toolName: String,
        input: [String: Any],
        timeZone: TimeZone
    ) -> [AssistantAction] {
        let formatter = dateFormatter(timeZone: timeZone)

        switch toolName {
        case createEvents:
            guard let rawEvents = input["events"] as? [[String: Any]] else { return [] }
            return rawEvents.compactMap { spec(from: $0, formatter: formatter) }
                .map { AssistantAction.createEvent($0) }

        case deleteEvent:
            guard let idString = input["id"] as? String, let id = UUID(uuidString: idString) else {
                return []
            }
            // Title and date are filled in by the caller, which can look the
            // entry up; placeholders here keep this function store-independent.
            return [.deleteEvent(id: id, title: "", date: Date())]

        case rescheduleEvent:
            guard let idString = input["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let startText = input["start"] as? String,
                  let endText = input["end"] as? String,
                  let start = formatter.date(from: startText),
                  let end = formatter.date(from: endText),
                  end > start
            else { return [] }
            return [.rescheduleEvent(id: id, title: "", newStart: start, newEnd: end)]

        case createSubject:
            guard let name = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { return [] }
            return [.createSubject(name: name)]

        case enableSchool:
            return [.enableSchool]

        default:
            return []
        }
    }

    private static func spec(from raw: [String: Any], formatter: DateFormatter) -> EventSpec? {
        guard let typeRaw = raw["type"] as? String,
              let type = EventType(rawValue: typeRaw),
              let startText = raw["start"] as? String,
              let endText = raw["end"] as? String,
              let start = formatter.date(from: startText),
              let end = formatter.date(from: endText),
              end > start
        else { return nil }

        let rateCents = raw["rate_cents"] as? Int
        let compensation = (raw["compensation_type"] as? String).flatMap(CompensationType.init(rawValue:))
        let resolvedCompensation: CompensationType? = type == .work
            ? (compensation ?? (rateCents == nil ? nil : .hourly))
            : nil

        return EventSpec(
            title: (raw["title"] as? String) ?? "",
            type: type,
            startDate: start,
            endDate: end,
            address: (raw["address"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            // No rate and no type means pay simply isn't tracked; a bare rate
            // is taken as hourly. Defaulting to hourly regardless used to
            // invent a rate-less hourly shift that then failed validation.
            compensationType: resolvedCompensation,
            hourlyRateCents: resolvedCompensation == .hourly ? rateCents : nil,
            fixedRateCents: resolvedCompensation == .fixed ? rateCents : nil,
            schoolKind: type == .school
                ? ((raw["school_kind"] as? String).flatMap(SchoolEventKind.init(rawValue:)) ?? .other)
                : nil,
            subjectName: type == .school ? raw["subject_name"] as? String : nil,
            notes: (raw["notes"] as? String).map { String($0.prefix(Event.notesCharacterLimit)) }
        )
    }

    /// The system prompt. Stable across turns so it stays cacheable.
    static func systemPrompt(context: AssistantContext) -> String {
        let formatter = dateFormatter(timeZone: TimeZone(identifier: context.timeZoneIdentifier) ?? .current)

        var lines: [String] = [
            "You are the scheduling assistant inside Shift, a calendar app for people with changing schedules and changing pay.",
            "",
            "Current local date and time: \(formatter.string(from: context.today)).",
            "Time zone: \(context.timeZoneIdentifier). Locale: \(context.localeIdentifier). Currency: EUR.",
            "School section is \(context.schoolEnabled ? "enabled" : "disabled").",
        ]

        if !context.subjectNames.isEmpty {
            lines.append("Existing subjects: \(context.subjectNames.joined(separator: ", ")).")
        }
        if !context.presetNames.isEmpty {
            lines.append("Existing presets: \(context.presetNames.joined(separator: ", ")).")
        }

        if !context.upcomingEvents.isEmpty {
            lines.append("")
            lines.append("Nearby entries (use these ids to modify or delete):")
            for event in context.upcomingEvents.prefix(60) {
                lines.append("- \(event.id.uuidString) | \(event.type.rawValue) | \(formatter.string(from: event.start)) to \(formatter.string(from: event.end)) | \(event.title)")
            }
        }

        lines.append(contentsOf: [
            "",
            "How to work:",
            "- Use the tools to propose changes. You cannot write to the calendar directly; every proposal is shown to the user, who approves or rejects it.",
            "- All times are local wall-clock in the format \(dateFormat), with no time zone offset.",
            "- Money is integer cents. 12.50 euros is 1250.",
            "- Expand every repeating request into individual entries yourself, applying skip rules (alternate weeks, public holidays, term dates) as you go. Do not ask the app to repeat anything.",
            "- A work entry may record pay, but does not have to: omit compensation_type and rate_cents when the user does not track pay, for example on a fixed monthly wage. A school entry needs a kind and a subject. Notes are optional and capped at 250 characters.",
            "- If the user asks for something school-related while School is disabled, propose enable_school first and say why.",
            "- If a school subject does not exist yet, propose create_subject before the entry that needs it.",
            "",
            "When you are missing something you genuinely need — a rate, an end time, which of two entries they meant — ask one short question instead of guessing. Otherwise act: make the routine judgement calls yourself and say briefly what you assumed.",
            "Keep replies short and conversational. Do not restate the whole list of entries you just proposed; the user can already see them.",
        ])

        return lines.joined(separator: "\n")
    }
}
