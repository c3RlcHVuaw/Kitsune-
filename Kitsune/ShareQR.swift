#if os(macOS)
import CoreImage.CIFilterBuiltins
import SwiftUI

/// QR code with the proxy address, login and password, for phones and TVs on the same network.
struct ShareQRView: View {
    let address: String
    let password: String
    @Environment(\.dismiss) private var dismiss

    private var payload: String { "socks5://\(LANSharing.username):\(password)@\(address)" }

    private var image: NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: .init(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("QR-код раздачи").font(.display(18, relativeTo: .headline))
            if let image {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 220, height: 220)
                    .padding(12).background(.white, in: .rect(cornerRadius: 16))
            }
            Text("Покажите камере или приложению с поддержкой прокси. Работает только в этой сети. Не показывайте код посторонним: в нём пароль.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text(verbatim: address).font(.callout.monospacedDigit()).textSelection(.enabled)
            Button("Готово") { dismiss() }.buttonStyle(.brand).frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: 340)
    }
}
#endif
