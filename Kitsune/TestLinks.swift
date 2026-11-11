#if DEBUG
/// Debug-only: a well-formed link to a non-existent server (203.0.113.0/24 is a documentation range). Not compiled into Release/IPA.
enum TestLinks {
    static let vless = "vless://7f3c9a2e-5b1d-4e8a-9c6f-2d4b8e1a3f57@203.0.113.42:443?type=tcp&security=reality&pbk=Qm9vbGVhbkZveEtpdHN1bmVUZXN0S2V5MTIzNDU2Nzg&sid=6ba85179&sni=www.apple.com&fp=chrome&flow=xtls-rprx-vision#Kitsune%20Test"
}
#endif
