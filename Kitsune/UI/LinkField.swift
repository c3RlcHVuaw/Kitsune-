import SwiftUI

/// Glass field for a server link or subscription URL with Paste and Test-link buttons. Used by onboarding and the server sheet.
struct LinkField: View {
    @Binding var link: String
    var error: String?
    var placeholder = "Ссылка на сервер или подписку"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(placeholder, text: $link, axis: .vertical)
                .lineLimit(1...3)
                .technicalTextEntry()
                .privacySensitive()
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            GlassEffectContainer(spacing: 10) {
                // Side by side when they fit, stacked at large Dynamic Type sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { buttons }
                    VStack(spacing: 10) { buttons }
                }
                .font(.callout)
                .frame(maxWidth: .infinity)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Color.alert)
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        PasteButton(payloadType: String.self) { strings in
            if let first = strings.first { link = first.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .tint(.white.opacity(0.25))
        .fixedSize()
        #if os(macOS)
        Button("QR из файла", systemImage: "qrcode.viewfinder") { if let found = QRReader.pick() { link = found } }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular.interactive(), in: .capsule)
            .fixedSize()
        #endif
        #if DEBUG
        Button("Тестовая ссылка", systemImage: "testtube.2") { link = TestLinks.vless }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .brandFill(in: .capsule)
            .fixedSize()
        #endif
    }
}

#if os(macOS)
import AppKit
import CoreImage
import UniformTypeIdentifiers

/// Reads a QR code from an image file (a screenshot or a saved picture).
enum QRReader {
    @MainActor static func pick() -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = CIImage(contentsOf: url) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return (detector?.features(in: image).first as? CIQRCodeFeature)?.messageString
    }
}
#endif
