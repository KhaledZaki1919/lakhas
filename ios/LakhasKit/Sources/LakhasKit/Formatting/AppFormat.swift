import Foundation

/// Digit style for Arabic (PROJECT_PROMPT.md §2): Western 0–9 by default, Eastern ٠–٩ optional.
public enum DigitStyle: String, CaseIterable, Sendable {
    case western, eastern

    public static let defaultsKey = "digitStyle"
}

/// Number and date formatting that follows the app language and the digit-style setting.
/// SwiftUI's `Text(Int)` would use Arabic-Indic digits in Arabic, so views format through this.
public struct AppFormat: Sendable {
    public let language: String
    public let digits: DigitStyle

    public init(language: String, digits: DigitStyle) {
        self.language = language
        self.digits = digits
    }

    public static var current: AppFormat {
        let language = Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true ? "en" : "ar"
        let stored = UserDefaults.standard.string(forKey: DigitStyle.defaultsKey).flatMap(DigitStyle.init(rawValue:))
        return AppFormat(language: language, digits: stored ?? .western)
    }

    public var locale: Locale {
        guard language == "ar" else { return Locale(identifier: "en_US") }
        return Locale(identifier: digits == .western ? "ar@numbers=latn" : "ar@numbers=arab")
    }

    public func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    public func number(_ value: Double, fractionDigits: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(0...fractionDigits)).locale(locale))
    }

    /// Day of month as digits in the chosen style.
    public func day(_ date: Date, calendar: Calendar = .current) -> String {
        number(calendar.component(.day, from: date))
    }

    /// Very short weekday symbol ("ح" / "S") for the date strip.
    public func weekdayInitial(_ date: Date, calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.locale = locale
        let index = cal.component(.weekday, from: date) - 1
        return cal.veryShortWeekdaySymbols[index]
    }

    /// "الأحد، 12 أكتوبر" / "Sunday, Oct 12".
    public func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(language == "ar" ? .wide : .abbreviated).locale(locale))
    }
}
