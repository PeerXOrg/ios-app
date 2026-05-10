import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

public struct QRCodeView: View {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        if let image = Self.render(message: message) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel(Text("Pass QR code", bundle: .module))
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .aspectRatio(1, contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }

    private static func render(message: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
