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

@MainActor enum Clipboard {
    /// Copies and confirms with a toast; pass nil where the control already shows its own "Скопировано".
    static func copy(_ text: String, toast: String? = L("Скопировано")) {
        if let toast { Toaster.shared.show(toast) }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    static func read() -> String? {
        #if os(macOS)
        NSPasteboard.general.string(forType: .string)
        #else
        UIPasteboard.general.string
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

/// Quiet system sounds and trackpad haptics, each behind its own setting. No-ops on iOS (it has `sensoryFeedback`).
@MainActor enum Feedback {
    static func sound(_ name: String, volume: Float = 0.5) {
        #if os(macOS)
        guard UserDefaults.standard.object(forKey: "sounds") as? Bool ?? true else { return }
        // A copy, so a quick second call plays over the first instead of being swallowed.
        guard let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = volume
        sound.play()
        #endif
    }

    /// Felt only while a finger rests on the trackpad.
    static func tap(firm: Bool = false) {
        #if os(macOS)
        guard UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(firm ? .levelChange : .alignment, performanceTime: .now)
        #endif
    }
}
