// Médiathèque
// SPDX-License-Identifier: MIT
// See LICENSE in the project root for the full license text and copyright notice.

import Foundation

/// A VEVENT from `/cms/ical/id_article/{id}`.
public struct ICalEventDTO: Sendable, Equatable {
    public var uid: String?
    public var summary: String?
    public var start: Date?
    public var end: Date?
    public var location: String?
    public var latitude: Double?
    public var longitude: Double?
    public var descriptionText: String?
    public var descriptionHTML: String?
    public var url: URL?
    public var imageURL: URL?
    public var categories: [String] = []
}

/// Minimal RFC 5545 parser: it covers what Bokeh produces
/// (folded lines, `TZID=Europe/Paris`, `GEO`, `X-ALT-DESC`).
public enum ICalParser {
    public static func events(from text: String) -> [ICalEventDTO] {
        var events: [ICalEventDTO] = []
        var current: ICalEventDTO?

        for line in unfold(text) {
            let property = Property(line)
            switch (property.name, property.value) {
            case ("BEGIN", "VEVENT"):
                current = ICalEventDTO()
            case ("END", "VEVENT"):
                if let event = current { events.append(event) }
                current = nil
            default:
                guard current != nil else { continue }
                apply(property, to: &current!)
            }
        }
        return events
    }

    private static func apply(_ property: Property, to event: inout ICalEventDTO) {
        switch property.name {
        case "UID": event.uid = property.value
        case "SUMMARY": event.summary = unescape(property.value)
        case "LOCATION": event.location = unescape(property.value)
        case "DESCRIPTION": event.descriptionText = unescape(property.value).trimmingCharacters(in: .whitespacesAndNewlines)
        case "X-ALT-DESC": event.descriptionHTML = unescape(property.value)
        case "URL": event.url = URL(string: property.value)
        case "ATTACH": event.imageURL = URL(string: property.value)
        case "CATEGORIES": event.categories = property.value.split(separator: ",").map { String($0) }
        case "DTSTART": event.start = date(property)
        case "DTEND": event.end = date(property)
        case "GEO":
            let parts = property.value.split(separator: ";").compactMap { Double($0) }
            if parts.count == 2 {
                event.latitude = parts[0]
                event.longitude = parts[1]
            }
        default: break
        }
    }

    /// Unfolds folded lines (a line starting with a space continues the previous one).
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else {
                lines.append(String(raw))
            }
        }
        return lines
    }

    static func unescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func date(_ property: Property) -> Date? {
        let value = property.value
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if value.hasSuffix("Z") {
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        } else if value.count == 8 {
            formatter.timeZone = TimeZone(identifier: property.parameters["TZID"] ?? "Europe/Paris")
            formatter.dateFormat = "yyyyMMdd"
        } else {
            formatter.timeZone = TimeZone(identifier: property.parameters["TZID"] ?? "Europe/Paris")
            formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        }
        return formatter.date(from: value)
    }

    /// `NOM;PARAM=val;…:valeur`. Bokeh sometimes produces odd parameters
    /// (`ATTACH;X-BKH-=IMAGE:https://…`): we split at the first `:` outside quotes.
    struct Property {
        let name: String
        let parameters: [String: String]
        let value: String

        init(_ line: String) {
            var inQuotes = false
            var splitIndex: String.Index?
            for index in line.indices {
                let character = line[index]
                if character == "\"" { inQuotes.toggle() }
                if character == ":", !inQuotes { splitIndex = index; break }
            }
            guard let splitIndex else {
                name = line
                parameters = [:]
                value = ""
                return
            }
            let head = line[..<splitIndex].split(separator: ";").map(String.init)
            name = head.first?.uppercased() ?? ""
            var parameters: [String: String] = [:]
            for parameter in head.dropFirst() {
                let pair = parameter.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 { parameters[pair[0].uppercased()] = pair[1] }
            }
            self.parameters = parameters
            value = String(line[line.index(after: splitIndex)...])
        }
    }
}
