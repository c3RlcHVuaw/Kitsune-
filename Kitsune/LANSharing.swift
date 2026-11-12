#if os(macOS)
import Foundation
import Shared

/// Settings and secrets for sharing the tunnel with other devices on the local network (macOS only).
enum LANSharing {
    static let enabledKey = "lanShare"
    static let port = 7890
    static let username = "kitsune"

    /// nil when sharing is off; the config builder additionally refuses weak passwords.
    static var current: LANShare? {
        guard UserDefaults.standard.bool(forKey: enabledKey) else { return nil }
        return LANShare(port: port, username: username, password: password())
    }

    /// A random 20-character password, created on first use and kept in the Keychain.
    static func password() -> String {
        if let stored = Keychain.string("lanSharePassword"), stored.count >= 12 { return stored }
        return regenerate()
    }

    @discardableResult static func regenerate() -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var generator = SystemRandomNumberGenerator()
        let new = String((0..<20).map { _ in alphabet.randomElement(using: &generator)! })
        Keychain.set(new, for: "lanSharePassword")
        return new
    }

    /// First private IPv4 address of this Mac (Wi-Fi or Ethernet), the one other devices should connect to.
    static func localAddress() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET), String(cString: interface.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let address = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            if address.hasPrefix("192.168.") || address.hasPrefix("10.") || address.hasPrefix("172.") { return address }
        }
        return nil
    }
}
#endif
