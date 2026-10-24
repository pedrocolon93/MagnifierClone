import CoreGraphics
import CoreImage
import Foundation
import ImageIO

/// A frozen camera frame: the upright full buffer plus the region currently visible on screen.
nonisolated struct FrozenFrame: Sendable {
    /// Upright, full buffer, extent origin at `.zero`. (CIImage is Sendable.)
    let image: CIImage
    /// Visible region in image pixels, top-left origin.
    let visibleRect: CGRect
}

nonisolated enum FrameCropper {
    private static let context = CIContext()

    enum CropError: Error {
        case encodingFailed
    }

    /// The image-pixel rect shown in the top `viewSize.height - obscuredBottom` points of an aspect-filled view.
    static func visibleRect(imageSize: CGSize, viewSize: CGSize, obscuredBottom: CGFloat) -> CGRect? {
        guard viewSize.width > 0, viewSize.height > 0, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let visibleHeight = viewSize.height - obscuredBottom
        guard visibleHeight > 0 else { return nil }

        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let shownWidth = viewSize.width / scale
        let shownHeight = viewSize.height / scale
        let originX = (imageSize.width - shownWidth) / 2
        let originY = (imageSize.height - shownHeight) / 2
        return CGRect(x: originX, y: originY, width: shownWidth, height: visibleHeight / scale)
    }

    static func croppedImage(_ frame: FrozenFrame) -> CIImage {
        let extent = frame.image.extent
        let rect = frame.visibleRect
        let flipped = CGRect(x: rect.minX, y: extent.height - rect.maxY, width: rect.width, height: rect.height)
        return frame.image
            .cropped(to: flipped)
            .transformed(by: CGAffineTransform(translationX: -flipped.minX, y: -flipped.minY))
    }

    static func cloudJPEG(_ frame: FrozenFrame, maxLongEdge: CGFloat = 1536, quality: CGFloat = 0.8) throws -> URL {
        var image = croppedImage(frame)
        let longEdge = max(image.extent.width, image.extent.height)
        if longEdge > maxLongEdge {
            let filter = CIFilter(name: "CILanczosScaleTransform")
            filter?.setValue(image, forKey: kCIInputImageKey)
            filter?.setValue(maxLongEdge / longEdge, forKey: kCIInputScaleKey)
            filter?.setValue(1.0, forKey: kCIInputAspectRatioKey)
            if let output = filter?.outputImage { image = output }
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let data = context.jpegRepresentation(
                of: image, colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
              ) else { throw CropError.encodingFailed }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ask-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }
}
