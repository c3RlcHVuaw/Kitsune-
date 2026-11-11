import Foundation

/// RFC 3492 encoder, enough to turn `пример.рф` into `xn--e1afmkfd.xn--p1ai` for routing rules.
enum Punycode {
    private static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700, initialBias = 72, initialN = 128

    /// Lowercased domain with every non-ASCII label encoded; nil if a label can't be encoded.
    static func toASCII(_ domain: String) -> String? {
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        for label in labels {
            if label.allSatisfy(\.isASCII) { out.append(label); continue }
            guard let encoded = encode(label) else { return nil }
            out.append("xn--" + encoded)
        }
        return out.joined(separator: ".")
    }

    private static func adapt(_ delta: Int, _ points: Int, _ first: Bool) -> Int {
        var delta = first ? delta / damp : delta / 2
        delta += delta / points
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 { delta /= base - tMin; k += base }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }

    private static func digit(_ d: Int) -> Character { Character(UnicodeScalar(d < 26 ? d + 97 : d - 26 + 48)!) }

    static func encode(_ input: String) -> String? {
        let scalars = input.unicodeScalars.map { Int($0.value) }
        var output = scalars.filter { $0 < 128 }.map { Character(UnicodeScalar($0)!) }
        let basic = output.count
        var handled = basic
        if basic > 0 { output.append("-") }
        var n = initialN, delta = 0, bias = initialBias
        while handled < scalars.count {
            guard let m = scalars.filter({ $0 >= n }).min() else { return nil }
            let (product, overflow) = (m - n).multipliedReportingOverflow(by: handled + 1)
            let (sum, overflow2) = delta.addingReportingOverflow(product)
            guard !overflow, !overflow2 else { return nil }
            delta = sum
            n = m
            for c in scalars {
                if c < n { delta += 1 }
                if c == n {
                    var q = delta, k = base
                    while true {
                        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                        if q < t { break }
                        output.append(digit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(digit(q))
                    bias = adapt(delta, handled + 1, handled == basic)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return String(output)
    }
}
