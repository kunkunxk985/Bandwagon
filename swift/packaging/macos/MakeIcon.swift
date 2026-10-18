import AppKit
import SwiftUI

// Source of the app icon. `scripts/make-icon.sh` compiles and runs this to write
// every size of packaging/macos/icon.iconset plus icon.png. Each size is rendered
// from the vectors at that size, not scaled down from 1024, so the ring stays
// crisp at 16 px.
//
// Geometry follows the macOS icon grid: a 1024 canvas with an 824 continuous-
// corner body. The ring is the same shape as `BrandMark` in the app's sidebar:
// a faint full track and a 250° arc from twelve o'clock, round caps.

private let canvas: CGFloat = 1024
private let bodySize: CGFloat = 824
private let corner: CGFloat = 185
private let ringDiameter: CGFloat = 470
private let ringWidth: CGFloat = 78

private func color(_ hex: UInt32) -> Color {
    Color(.sRGB,
          red: Double((hex >> 16) & 0xFF) / 255,
          green: Double((hex >> 8) & 0xFF) / 255,
          blue: Double(hex & 0xFF) / 255)
}

private struct RingArc: Shape {
    var degrees: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2,
                    startAngle: .degrees(-90), endAngle: .degrees(degrees - 90), clockwise: false)
        return path
    }
}

private struct AppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [color(0x3B78F2), color(0x1D4FC4)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 2)
                )
                .frame(width: bodySize, height: bodySize)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: ringWidth)
                .frame(width: ringDiameter, height: ringDiameter)
            RingArc(degrees: 250)
                .stroke(Color.white, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .frame(width: ringDiameter, height: ringDiameter)
        }
        .frame(width: canvas, height: canvas)
    }
}

@MainActor
private func write(pixels: Int, to url: URL) throws {
    let renderer = ImageRenderer(content: AppIcon())
    renderer.scale = CGFloat(pixels) / canvas
    guard let image = renderer.cgImage,
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

@main
struct MakeIcon {
    @MainActor static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
        let iconset = out.appendingPathComponent("icon.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 64, 128, 256, 512] {
            try write(pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
            try write(pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
        }
        try write(pixels: 1024, to: iconset.appendingPathComponent("icon_1024x1024.png"))
        try write(pixels: 1024, to: out.appendingPathComponent("icon.png"))
        print("wrote \(iconset.path)")
    }
}
