import SwiftUI

/// A tick colour per country, close to the flag, so a country is easy to spot in a list of hundreds.
enum CountryColor {
    private static let table: [String: Color] = [
        "NL": .orange, "SE": .blue, "DE": .yellow, "LV": Color(red: 0.6, green: 0.15, blue: 0.2), "EE": .cyan, "PL": .red,
        "FI": .blue, "IT": .green, "CH": .red, "NO": .red, "FR": .indigo, "GB": .blue, "US": .blue, "UA": .yellow,
        "TR": .red, "ES": .orange, "AT": .red, "CZ": .blue, "KZ": .teal, "JP": .pink, "SG": .red, "HK": .red,
        "CA": .red, "LT": .green, "RO": .yellow, "BG": .green, "RS": .red, "AM": .orange, "GE": .red, "EU": .blue,
    ]

    static func of(_ code: String?) -> Color {
        guard let code else { return .gray }
        if let color = table[code] { return color }
        // Unknown country: a stable hue from the letters, so it still has its own colour.
        let hue = Double(code.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) } % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.9)
    }
}
