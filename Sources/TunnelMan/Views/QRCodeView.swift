import SwiftUI
import CoreImage.CIFilterBuiltins

struct QRCodeView: View {
    let url: URL

    var body: some View {
        if let image = generateQRCode(from: url.absoluteString) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .cornerRadius(8)
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 200, height: 200)
                .overlay(Text("QR unavailable").foregroundColor(.secondary))
        }
    }

    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up for crisp display
        let scale: CGFloat = 10
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: transformed.extent.width, height: transformed.extent.height))
    }
}
