//
//  Money.swift
//  Shift
//

import Foundation

/// Currency handling. Amounts are stored as integer cents everywhere so that
/// summing a month of shifts never accumulates floating-point error.
enum Money {
    /// Fixed per the project decision: the app is priced in euros regardless of
    /// device region. Only the *formatting* conventions follow the locale.
    static let currencyCode = "EUR"

    static func string(cents: Int, locale: Locale = .current) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: currencyCode).locale(locale))
    }

    /// Parses user input into cents, accepting either a comma or a dot as the
    /// decimal separator so a Spanish user typing "12,50" is not rejected.
    ///
    /// Returns nil for anything that is not a plain non-negative amount.
    static func cents(from input: String) -> Int? {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: Money.currencySymbol, with: "")
            .replacingOccurrences(of: ",", with: ".")

        guard !trimmed.isEmpty else { return nil }
        // Reject thousands separators and other stray punctuation outright
        // rather than silently misreading "1.234" as €1.23.
        guard trimmed.filter({ $0 == "." }).count <= 1 else { return nil }
        guard trimmed.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        guard let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        guard value >= 0 else { return nil }

        let scaled = value * 100
        var rounded = Decimal()
        var mutable = scaled
        NSDecimalRound(&rounded, &mutable, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// The bare amount without a currency symbol, for pre-filling text fields.
    static func editableString(cents: Int, locale: Locale = .current) -> String {
        (Decimal(cents) / 100).formatted(
            .number.precision(.fractionLength(2)).grouping(.never).locale(locale)
        )
    }

    static var currencySymbol: String {
        Locale.current.localizedCurrencySymbol(forCurrencyCode: currencyCode) ?? "€"
    }
}

private extension Locale {
    func localizedCurrencySymbol(forCurrencyCode code: String) -> String? {
        guard let symbol = (self as NSLocale).displayName(forKey: .currencySymbol, value: code) else {
            return nil
        }
        return symbol
    }
}
