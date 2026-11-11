import Foundation

/// A `vless://` share link: TCP / gRPC / WebSocket transport over Reality, TLS or plain.
public struct VLESSLink: Equatable, Sendable {
    public var name: String
    public var host: String
    public var port: Int
    public var uuid: String
    public var flow: String?
    public var security: String // reality | tls | none
    public var transport: String // tcp | grpc | ws
    public var serverName: String?
    public var publicKey: String?
    public var shortID: String
    public var fingerprint: String?
    public var serviceName: String? // grpc
    public var path: String? // ws
    public var hostHeader: String? // ws

    public enum ParseError: Error, Equatable {
        case notVLESS, missing(String), unsupported(String)
    }

    public init(_ link: String) throws(ParseError) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: trimmed), url.scheme?.lowercased() == "vless" else { throw .notVLESS }
        let query = url.queryDictionary
        guard let uuid = url.user, !uuid.isEmpty else { throw .missing("uuid") }
        guard let host = url.host, !host.isEmpty else { throw .missing("host") }
        guard let port = url.port, (1...65535).contains(port) else { throw .missing("port") }

        let security = query["security"] ?? "none"
        guard ["reality", "tls", "none"].contains(security) else { throw .unsupported("security=\(security)") }
        let transport = query["type"] ?? "tcp"
        guard ["tcp", "grpc", "ws"].contains(transport) else { throw .unsupported("type=\(transport)") }

        self.uuid = uuid
        // URLComponents keeps IPv6 brackets in host; sing-box wants the bare address.
        self.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        self.port = port
        self.flow = query["flow"]
        self.security = security
        self.transport = transport
        self.serverName = query["sni"]
        self.publicKey = query["pbk"]
        self.shortID = query["sid"] ?? ""
        self.fingerprint = query["fp"]
        self.serviceName = query["serviceName"]
        self.path = query["path"]
        self.hostHeader = query["host"]
        if security == "reality" {
            guard serverName != nil else { throw .missing("sni") }
            guard publicKey != nil else { throw .missing("pbk") }
            if fingerprint == nil { fingerprint = "chrome" } // Reality requires uTLS
        }
        self.name = url.fragment.flatMap { $0.isEmpty ? nil : $0 } ?? self.host
    }

    /// sing-box outbound (without tag).
    public var outbound: [String: Any] {
        var outbound: [String: Any] = ["type": "vless", "server": host, "server_port": port, "uuid": uuid]
        if let flow { outbound["flow"] = flow }
        if security != "none" {
            var tls: [String: Any] = ["enabled": true]
            if let serverName { tls["server_name"] = serverName }
            if let fingerprint { tls["utls"] = ["enabled": true, "fingerprint": fingerprint] }
            if security == "reality", let publicKey {
                tls["reality"] = ["enabled": true, "public_key": publicKey, "short_id": shortID]
            }
            outbound["tls"] = tls
        }
        switch transport {
        case "grpc": outbound["transport"] = ["type": "grpc", "service_name": serviceName ?? ""]
        case "ws":
            var ws: [String: Any] = ["type": "ws", "path": path ?? "/"]
            if let hostHeader { ws["headers"] = ["Host": hostHeader] }
            outbound["transport"] = ws
        default: break
        }
        return outbound
    }

    public var summary: String {
        ["VLESS", transport.uppercased().replacingOccurrences(of: "GRPC", with: "gRPC"), security == "none" ? nil : security == "tls" ? "TLS" : "Reality"]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

extension URLComponents {
    /// Query items as a dictionary; empty values dropped, last duplicate wins.
    var queryDictionary: [String: String] {
        Dictionary((queryItems ?? []).compactMap { item in item.value.flatMap { $0.isEmpty ? nil : (item.name, $0) } },
                   uniquingKeysWith: { _, last in last })
    }
}
