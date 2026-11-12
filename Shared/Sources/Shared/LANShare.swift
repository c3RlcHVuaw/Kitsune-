import Foundation

/// A password-protected proxy other devices on the local network can use; their traffic leaves through the tunnel.
public struct LANShare: Sendable, Equatable {
    public var port: Int
    public var username: String
    public var password: String

    public init(port: Int, username: String, password: String) {
        self.port = port
        self.username = username
        self.password = password
    }

    /// An open or weak proxy on a LAN is worse than none: refuse short passwords and bad ports.
    public var isSafe: Bool { password.count >= 12 && !username.isEmpty && (1024...65535).contains(port) }
}
