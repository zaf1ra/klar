import SwiftUI
import UIKit

// MARK: Glas und Übergänge

extension View {
    /// Glas im Stil von iOS 26 („Liquid Glass“). Auf älteren Systemen Milchglas.
    @ViewBuilder
    func glass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }

    /// Quelle für den Zoom-Übergang (Kachel → Vollbild).
    @ViewBuilder
    func zoomSource(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Vollbild zoomt aus der Kachel heraus und beim Schließen wieder hinein.
    @ViewBuilder
    func zoomTransition(id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

/// Fasst mehrere Glas-Elemente zusammen, damit sie wie ein Stück Glas ineinanderfließen.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Knöpfe geben beim Drücken federnd nach.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: Hintergrund

/// Ruhiger, fast farbloser Verlauf. Glas braucht etwas dahinter, sonst wirkt es flach –
/// aber nichts, was das Auge reizt.
struct SlopBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let colors: [Color] = scheme == .dark
            ? [.init(white: 0.10), .init(white: 0.06), .init(white: 0.12),
               .init(white: 0.05), .init(white: 0.09), .init(white: 0.04),
               .init(white: 0.08), .init(white: 0.03), .init(white: 0.07)]
            : [.init(red: 0.95, green: 0.94, blue: 0.92), .init(white: 0.97), .init(red: 0.93, green: 0.93, blue: 0.95),
               .init(white: 0.96), .init(red: 0.90, green: 0.90, blue: 0.91), .init(white: 0.95),
               .init(red: 0.93, green: 0.92, blue: 0.90), .init(white: 0.94), .init(red: 0.91, green: 0.92, blue: 0.94)]
        Group {
            if #available(iOS 18, *) {
                MeshGradient(width: 3, height: 3, points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [0.6, 0.45], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ], colors: colors)
            } else {
                LinearGradient(colors: [colors[0], colors[8]], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: App-Icons der Dienste

/// Lädt das Original-Icon eines Dienstes einmal, bereitet es auf (Hintergrund, Einfärben)
/// und speichert es. Danach erscheint es sofort, auch offline.
@MainActor
@Observable
final class IconStore {
    static let shared = IconStore()
    private(set) var images: [String: UIImage] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    private static var folder: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("icons")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func image(for site: SiteRules) -> UIImage? {
        guard let source = site.iconURL else { return nil }
        let key = cacheKey(site, source)
        if let image = images[key] { return image }
        let file = Self.folder.appendingPathComponent(key + ".png")
        if let image = UIImage(contentsOfFile: file.path) {
            images[key] = image
            return image
        }
        load(site, source: source, key: key, file: file)
        return nil
    }

    /// Stabil über App-Starts hinweg (Swifts hashValue ändert sich bei jedem Start).
    private func cacheKey(_ site: SiteRules, _ source: String) -> String {
        let style = "\(source)|\(site.iconBackground ?? "")|\(site.iconScale ?? 1)|\(site.iconFlood ?? "")"
        var hash: UInt64 = 0xcbf29ce484222325  // FNV-1a
        for byte in style.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return site.id + "-" + String(hash, radix: 36)
    }

    private func load(_ site: SiteRules, source: String, key: String, file: URL) {
        guard !loading.contains(key), let url = URL(string: source) else { return }
        loading.insert(key)
        Task {
            defer { loading.remove(key) }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let raw = UIImage(data: data),
                  let icon = Self.render(raw, site: site) else { return }
            try? icon.pngData()?.write(to: file)
            withAnimation(.smooth) { images[key] = icon }
        }
    }

    /// Setzt das Logo auf seinen Hintergrund bzw. färbt die äußere Fläche ein.
    private static func render(_ raw: UIImage, site: SiteRules) -> UIImage? {
        let size = CGSize(width: 180, height: 180)
        var logo = raw
        if let flood = site.iconFlood.flatMap(UIColor.init(hex:)), let filled = floodFill(raw, with: flood) {
            logo = filled
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            if let background = site.iconBackground.flatMap(UIColor.init(hex:)) {
                background.setFill()
                UIRectFill(CGRect(origin: .zero, size: size))
            }
            let scale = min(max(site.iconScale ?? 1, 0.1), 1)
            let aspect = logo.size.width / max(logo.size.height, 1)
            var target = CGSize(width: size.width * scale, height: size.height * scale)
            if aspect > 1 { target.height = target.width / aspect } else { target.width = target.height * aspect }
            logo.draw(in: CGRect(x: (size.width - target.width) / 2, y: (size.height - target.height) / 2,
                                 width: target.width, height: target.height))
        }
    }

    /// Färbt alle hellen Pixel ein, die vom Bildrand aus ohne Linie erreichbar sind.
    /// So bleibt z. B. der weiße Snapchat-Geist weiß, sein Umfeld wird gelb.
    private static func floodFill(_ image: UIImage, with color: UIColor) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        // data: nil – der Kontext verwaltet seinen Speicher selbst, solange er lebt.
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = ctx.data else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytesPerRow = ctx.bytesPerRow
        let pixels = raw.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let fill = [UInt8(r * 255), UInt8(g * 255), UInt8(b * 255), 255]
        func offset(_ x: Int, _ y: Int) -> Int { y * bytesPerRow + x * 4 }
        func isLight(_ i: Int) -> Bool {
            pixels[i + 3] < 40 || (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) > 600
        }

        var visited = [Bool](repeating: false, count: width * height)
        var stack: [(Int, Int)] = []
        for x in 0..<width { stack.append((x, 0)); stack.append((x, height - 1)) }
        for y in 0..<height { stack.append((0, y)); stack.append((width - 1, y)) }
        while let (x, y) = stack.popLast() {
            let index = y * width + x
            if visited[index] { continue }
            visited[index] = true
            let i = offset(x, y)
            guard isLight(i) else { continue }
            for c in 0..<4 { pixels[i + c] = fill[c] }
            if x > 0 { stack.append((x - 1, y)) }
            if x < width - 1 { stack.append((x + 1, y)) }
            if y > 0 { stack.append((x, y - 1)) }
            if y < height - 1 { stack.append((x, y + 1)) }
        }
        return ctx.makeImage().map(UIImage.init(cgImage:))
    }
}

/// Icon eines Dienstes in iOS-Form. Solange das Original lädt, steht ein schlichtes Symbol da.
struct AppIconView: View {
    let site: SiteRules
    var size: CGFloat = 60
    @State private var store = IconStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            if let image = store.image(for: site) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .transition(.opacity)
            } else {
                Image(systemName: site.icon)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glass(in: shape)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}

extension UIColor {
    /// "#RRGGBB"
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(red: CGFloat((number >> 16) & 0xFF) / 255,
                  green: CGFloat((number >> 8) & 0xFF) / 255,
                  blue: CGFloat(number & 0xFF) / 255, alpha: 1)
    }
}
