import Testing
@testable import Shared

@Test func tunnelBundleIDIsNestedUnderApp() {
    // iOS rejects an extension whose bundle ID is not prefixed by the app's.
    #expect(AppIdentifiers.tunnelBundleID.hasPrefix("com.kitsune.vpn."))
}
