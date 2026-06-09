import SwiftUI
import AppKit

final class ArtworkCache {
    private var colorsByTrack: [TrackIdentity: (Color, Color)] = [:]

    func colors(for track: NowPlayingTrack) -> (Color, Color) {
        if let cached = colorsByTrack[track.identity] {
            return cached
        }
        let colors = (track.dominantColor, track.secondaryColor)
        colorsByTrack[track.identity] = colors
        return colors
    }

    func clear() {
        colorsByTrack.removeAll()
    }
}

final class ArtworkAnalyzer {
    func colors(from image: NSImage?) -> (Color, Color) {
        guard let image,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return (
                Color(red: 0.43, green: 0.49, blue: 0.39),
                Color(red: 0.70, green: 0.55, blue: 0.35)
            )
        }

        let width = 1
        let height = 1
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (.secondary, Color(nsColor: .tertiaryLabelColor))
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let red = Double(pixel[0]) / 255
        let green = Double(pixel[1]) / 255
        let blue = Double(pixel[2]) / 255
        let dominant = Color(red: red, green: green, blue: blue)
        let secondary = Color(
            red: min(red * 1.18 + 0.08, 1),
            green: min(green * 1.12 + 0.08, 1),
            blue: min(blue * 1.08 + 0.08, 1)
        )
        return (dominant, secondary)
    }
}
