import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// iOS-only modifiers behind one name, so screens stay shared between iPhone and Mac.
extension View {
    /// Small centered navigation title (iOS); macOS has no such style.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Links, domains, IPs: no auto-capitalisation, URL keyboard on iPhone.
    func technicalTextEntry() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }

    /// Half-height sheet on iPhone; a fixed-size sheet window on Mac.
    func adaptiveSheet() -> some View {
        #if os(iOS)
        presentationDetents([.medium, .large])
        #else
        frame(minWidth: 440, minHeight: 380)
        #endif
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}

/// macOS hides large navigation titles under the hidden title bar and folds toolbar buttons behind the tabs,
/// so on Mac the screen title and its actions sit at the top of the content instead. iOS uses the navigation bar.
struct ScreenHeader<Actions: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        #if os(macOS)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.display(26, relativeTo: .largeTitle)).minimumScaleFactor(0.6).lineLimit(1)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer()
            HStack(spacing: 8) { actions }
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        #endif
    }
}

extension View {
    /// Navigation title and toolbar actions on iOS; nothing on macOS, where `ScreenHeader` shows them.
    func iOSNavigation<Actions: View>(title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) -> some View {
        #if os(iOS)
        navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
            .toolbar { ToolbarItemGroup(placement: .primaryAction) { actions() } }
        #else
        self
        #endif
    }
}
