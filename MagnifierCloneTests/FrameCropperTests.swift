import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
@testable import MagnifierClone

struct FrameCropperTests {
    private let imageSize = CGSize(width: 1080, height: 1920)
    private let viewSize = CGSize(width: 390, height: 844)

    @Test func visibleRectPortraitPhone() throws {
        let rect = try #require(FrameCropper.visibleRect(imageSize: imageSize, viewSize: viewSize, obscuredBottom: 300))
        #expect(abs(rect.origin.x - 96.40) < 0.5)
        #expect(abs(rect.origin.y - 0) < 0.5)
        #expect(abs(rect.width - 887.20) < 0.5)
        #expect(abs(rect.height - 1237.54) < 0.5)
    }

    @Test func visibleRectNoObstruction() throws {
        let rect = try #require(FrameCropper.visibleRect(imageSize: imageSize, viewSize: viewSize, obscuredBottom: 0))
        #expect(abs(rect.height - 1920) < 0.5)
    }

    @Test func visibleRectNilWhenFullyObscured() {
        #expect(FrameCropper.visibleRect(imageSize: imageSize, viewSize: viewSize, obscuredBottom: 844) == nil)
        #expect(FrameCropper.visibleRect(imageSize: imageSize, viewSize: viewSize, obscuredBottom: 900) == nil)
    }

    @Test func visibleRectNilForZeroView() {
        #expect(FrameCropper.visibleRect(imageSize: imageSize, viewSize: .zero, obscuredBottom: 0) == nil)
    }

    @Test func croppedImageTakesTopRegion() {
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 100, width: 100, height: 100))
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let image = red.composited(over: blue)
        let frame = FrozenFrame(image: image, visibleRect: CGRect(x: 0, y: 0, width: 100, height: 100))

        let cropped = FrameCropper.croppedImage(frame)
        #expect(cropped.extent == CGRect(x: 0, y: 0, width: 100, height: 100))

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext()
        context.render(cropped, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 50, y: 50, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        #expect(pixel[0] > 200)
        #expect(pixel[2] < 50)
    }

    private func pixelSize(of url: URL) throws -> (width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    private func solidFrame(width: CGFloat, height: CGFloat) -> FrozenFrame {
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let image = CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.4)).cropped(to: rect)
        return FrozenFrame(image: image, visibleRect: rect)
    }

    @Test func cloudJPEGDownscalesLongEdge() throws {
        let url = try FrameCropper.cloudJPEG(solidFrame(width: 3000, height: 4000))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FileManager.default.fileExists(atPath: url.path))
        let size = try pixelSize(of: url)
        #expect(size.height == 1536)
        #expect(size.width == 1152)
    }

    @Test func cloudJPEGKeepsSmallImages() throws {
        let url = try FrameCropper.cloudJPEG(solidFrame(width: 800, height: 600))
        defer { try? FileManager.default.removeItem(at: url) }
        let size = try pixelSize(of: url)
        #expect(size.width == 800)
        #expect(size.height == 600)
    }
}
