import Foundation
import ImageIO

/// Was sich aus der Bilddatei selbst über ihre Herkunft lesen lässt.
struct MetadataReport: Equatable {
    /// Die Datei trägt eine eindeutige KI-Kennzeichnung (Content Credentials, IPTC, Generator-Daten).
    var isAI = false
    /// Mit welcher KI bzw. Software, z. B. „ChatGPT (OpenAI)“ oder „Stable Diffusion“.
    var generator: String?
    var prompt: String?
    var negativePrompt: String?
    var model: String?
    var settings: String?
    /// Content Credentials (C2PA) vorhanden.
    var hasContentCredentials = false
    /// Kamera aus den EXIF-Daten, z. B. „Apple iPhone 15 Pro“.
    var camera: String?
    var software: String?
    var notes: [String] = []

    var isEmpty: Bool {
        !isAI && generator == nil && prompt == nil && !hasContentCredentials && camera == nil && software == nil
    }
}

/// Liest KI-Spuren aus Bilddateien: Content Credentials (C2PA), IPTC „DigitalSourceType“,
/// PNG-Textfelder von Stable Diffusion / ComfyUI / Midjourney / NovelAI / InvokeAI und EXIF.
enum MetadataInspector {
    static func inspect(_ data: Data) -> MetadataReport {
        var report = MetadataReport()
        let latin1 = String(data: data, encoding: .isoLatin1) ?? ""

        readImageIO(data, into: &report)
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            for (key, value) in pngTextChunks(data) { interpret(key: key, value: value, into: &report) }
        }
        readXMP(latin1, into: &report)
        readC2PA(data, latin1, into: &report)

        // Ein gefundener Prompt heißt immer: mit KI erzeugt.
        if report.prompt != nil { report.isAI = true }
        return report
    }

    // MARK: EXIF / TIFF / PNG über ImageIO

    private static func readImageIO(_ data: Data, into report: inout MetadataReport) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] ?? [:]

        if let make = tiff[kCGImagePropertyTIFFMake] as? String, let model = tiff[kCGImagePropertyTIFFModel] as? String {
            let trimmedMake = make.trimmingCharacters(in: .whitespaces)
            report.camera = model.hasPrefix(trimmedMake) ? model : "\(trimmedMake) \(model)"
        }
        if let software = tiff[kCGImagePropertyTIFFSoftware] as? String ?? png[kCGImagePropertyPNGSoftware] as? String {
            report.software = software
            interpret(key: "Software", value: software, into: &report)
        }
        // Stable Diffusion (A1111/Forge) schreibt bei JPEG/WebP die Parameter in den EXIF-Kommentar.
        if let comment = exif[kCGImagePropertyExifUserComment] as? String {
            interpret(key: "parameters", value: comment, into: &report)
        }
        if let description = tiff[kCGImagePropertyTIFFImageDescription] as? String {
            interpret(key: "Description", value: description, into: &report)
        }
    }

    // MARK: PNG-Textfelder

    /// tEXt, zTXt und iTXt eines PNG als (Schlüssel, Text).
    static func pngTextChunks(_ data: Data) -> [(String, String)] {
        var result: [(String, String)] = []
        let bytes = [UInt8](data)
        var offset = 8
        while offset + 8 <= bytes.count {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let type = String(bytes: bytes[offset + 4..<offset + 8], encoding: .ascii) ?? ""
            let start = offset + 8, end = start + length
            guard length >= 0, end <= bytes.count else { break }
            let body = Array(bytes[start..<end])
            if type == "IEND" { break }
            if let zero = body.firstIndex(of: 0), let key = String(bytes: body[..<zero], encoding: .isoLatin1) {
                switch type {
                case "tEXt":
                    result.append((key, String(bytes: body[(zero + 1)...], encoding: .isoLatin1) ?? ""))
                case "zTXt":
                    if zero + 2 <= body.count, let text = inflate(Array(body[(zero + 2)...])) {
                        result.append((key, String(decoding: text, as: UTF8.self)))
                    }
                case "iTXt":
                    // Schlüssel \0 Kompression Methode Sprache \0 übersetzter Schlüssel \0 Text
                    guard zero + 3 <= body.count else { break }
                    let compressed = body[zero + 1] == 1
                    var rest = Array(body[(zero + 3)...])
                    for _ in 0..<2 {
                        guard let next = rest.firstIndex(of: 0) else { rest = []; break }
                        rest = Array(rest[(next + 1)...])
                    }
                    let text = compressed ? inflate(rest) : rest
                    if let text { result.append((key, String(decoding: text, as: UTF8.self))) }
                default:
                    break
                }
            }
            offset = end + 4  // CRC überspringen
        }
        return result
    }

    /// zlib-Daten entpacken (2 Byte Kopf, DEFLATE, 4 Byte Prüfsumme).
    private static func inflate(_ bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count > 6 else { return nil }
        let raw = Data(bytes[2..<(bytes.count - 4)])
        guard let out = try? (raw as NSData).decompressed(using: .zlib) else { return nil }
        return [UInt8](out as Data)
    }

    // MARK: Generatoren erkennen

    private static func interpret(key: String, value: String, into report: inout MetadataReport) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        switch key.lowercased() {
        case "parameters":
            // AUTOMATIC1111 / Forge / Fooocus: Prompt, dann „Negative prompt:“, dann „Steps: …“
            guard text.contains("Steps:") || text.contains("Negative prompt:") || text.contains("Sampler:") else { return }
            report.isAI = true
            report.generator = report.generator ?? "Stable Diffusion"
            var promptPart = text
            if let steps = text.range(of: "\nSteps:") ?? text.range(of: "Steps:") {
                report.settings = String(text[steps.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                promptPart = String(text[..<steps.lowerBound])
            }
            if let negative = promptPart.range(of: "Negative prompt:") {
                report.negativePrompt = clean(String(promptPart[negative.upperBound...]))
                promptPart = String(promptPart[..<negative.lowerBound])
            }
            report.prompt = clean(promptPart)
            if let settings = report.settings, let model = firstMatch(#"Model: ([^,]+)"#, in: settings) {
                report.model = model
            }
        case "prompt", "workflow":
            // ComfyUI: Knoten als JSON
            guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return }
            report.isAI = true
            report.generator = report.generator ?? "ComfyUI (Stable Diffusion / Flux)"
            let nodes = json.compactMapValues { $0 as? [String: Any] }
            func inputs(_ id: String) -> [String: Any] { nodes[id]?["inputs"] as? [String: Any] ?? [:] }
            /// Text des Knotens, auf den ein Eingang verweist (Format: ["6", 0]).
            func linkedText(_ link: Any?) -> String? {
                guard let id = (link as? [Any])?.first.map({ "\($0)" }) else { return nil }
                return inputs(id)["text"] as? String
            }
            // Der Sampler sagt eindeutig, welcher Text positiv und welcher negativ ist.
            // JSON-Objekte haben keine feste Reihenfolge, daher nicht nach Position gehen.
            for (id, node) in nodes where (node["class_type"] as? String ?? "").contains("Sampler") {
                report.prompt = report.prompt ?? linkedText(inputs(id)["positive"]).flatMap(clean)
                report.negativePrompt = report.negativePrompt ?? linkedText(inputs(id)["negative"]).flatMap(clean)
            }
            let sortedIDs = nodes.keys.sorted { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }
            for id in sortedIDs {
                let values = inputs(id)
                if let checkpoint = values["ckpt_name"] as? String ?? values["unet_name"] as? String { report.model = checkpoint }
                if report.prompt == nil, (nodes[id]?["class_type"] as? String ?? "").contains("TextEncode"),
                   let text = values["text"] as? String {
                    report.prompt = clean(text)
                }
            }
        case "invokeai_metadata", "sd-metadata", "dream":
            report.isAI = true
            report.generator = report.generator ?? "InvokeAI"
            if let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                report.prompt = report.prompt ?? (json["positive_prompt"] as? String).flatMap(clean)
                report.negativePrompt = report.negativePrompt ?? (json["negative_prompt"] as? String).flatMap(clean)
                report.model = report.model ?? ((json["model"] as? [String: Any])?["name"] as? String)
            } else {
                report.prompt = report.prompt ?? clean(text)
            }
        case "comment":
            // NovelAI: Kommentar als JSON mit "prompt" und "uc" (unerwünschte Inhalte)
            if let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], json["prompt"] != nil {
                report.isAI = true
                report.generator = report.generator ?? "NovelAI"
                report.prompt = report.prompt ?? (json["prompt"] as? String).flatMap(clean)
                report.negativePrompt = report.negativePrompt ?? (json["uc"] as? String).flatMap(clean)
            }
        case "description":
            // Midjourney: Prompt plus „Job ID: …“
            if text.contains("Job ID:") || text.lowercased().contains("midjourney") {
                report.isAI = true
                report.generator = "Midjourney"
                let prompt = text.components(separatedBy: "Job ID:").first ?? text
                report.prompt = report.prompt ?? clean(prompt)
            } else if report.prompt == nil, report.generator == "NovelAI" {
                report.prompt = clean(text)
            }
        case "software", "author", "title":
            if let name = knownGenerator(in: text) {
                report.isAI = true
                report.generator = report.generator ?? name
            }
        default:
            break
        }
    }

    // MARK: XMP (IPTC DigitalSourceType)

    private static func readXMP(_ latin1: String, into report: inout MetadataReport) {
        guard let start = latin1.range(of: "<x:xmpmeta"), let end = latin1.range(of: "</x:xmpmeta>", range: start.upperBound..<latin1.endIndex) else { return }
        let xmp = String(latin1[start.lowerBound..<end.upperBound])
        if xmp.contains("trainedAlgorithmicMedia") {
            report.isAI = true
            report.notes.append(xmp.contains("compositeWithTrainedAlgorithmicMedia")
                ? "Laut IPTC-Metadaten teilweise mit KI erzeugt (z. B. generatives Füllen)."
                : "Laut IPTC-Metadaten vollständig mit KI erzeugt.")
        }
        if let tool = firstMatch(#"CreatorTool(?:="|>)([^"<]+)"#, in: xmp) {
            report.software = report.software ?? tool
            if let name = knownGenerator(in: tool) { report.generator = report.generator ?? name }
        }
    }

    // MARK: Content Credentials (C2PA)

    private static func readC2PA(_ data: Data, _ latin1: String, into report: inout MetadataReport) {
        guard latin1.contains("jumb"), latin1.contains("c2pa") else { return }
        report.hasContentCredentials = true
        let bytes = [UInt8](data)

        var generators: [String] = []
        if let value = cborText(after: "claim_generator", in: bytes) { generators.append(value) }
        // C2PA 2.x: claim_generator_info: [{ name: "…", version: "…" }]
        if let range = latin1.range(of: "claim_generator_info") {
            let offset = latin1.distance(from: latin1.startIndex, to: range.upperBound)
            if let name = cborText(after: "name", in: Array(bytes[offset..<min(bytes.count, offset + 300)])) {
                generators.append(name)
            }
        }
        if let softwareAgent = cborText(after: "softwareAgent", in: bytes) { generators.append(softwareAgent) }

        let combined = generators.joined(separator: " ")
        // Nur in den gelesenen Feldern suchen, nicht in der ganzen Datei: Kurze Namen wie
        // „sora“ kämen in Bilddaten sonst zufällig vor.
        let known = knownGenerator(in: combined)
        if let known {
            report.generator = report.generator ?? known
        } else if let first = generators.first {
            report.software = report.software ?? first
        }
        if latin1.contains("trainedAlgorithmicMedia") {
            report.isAI = true
            report.notes.append(latin1.contains("compositeWithTrainedAlgorithmicMedia")
                ? "Content Credentials: Bild wurde teilweise mit KI erzeugt."
                : "Content Credentials: Bild wurde mit KI erzeugt.")
        } else if known != nil {
            report.isAI = true
        } else {
            report.notes.append("Content Credentials vorhanden, aber ohne KI-Vermerk.")
        }
    }

    /// Liest den CBOR-Text, der auf den Textschlüssel `key` folgt.
    static func cborText(after key: String, in bytes: [UInt8]) -> String? {
        let keyBytes = Array(key.utf8)
        guard keyBytes.count < 24 else { return nil }
        let pattern = [UInt8(0x60 + keyBytes.count)] + keyBytes
        guard let index = find(pattern, in: bytes) else { return nil }
        var i = index + pattern.count
        guard i < bytes.count else { return nil }
        let head = bytes[i]
        guard head >> 5 == 3 else { return nil }  // Haupttyp 3 = Text
        var length = Int(head & 0x1F)
        i += 1
        if length == 24, i < bytes.count { length = Int(bytes[i]); i += 1 }
        else if length == 25, i + 1 < bytes.count { length = Int(bytes[i]) << 8 | Int(bytes[i + 1]); i += 2 }
        else if length > 25 { return nil }
        guard i + length <= bytes.count else { return nil }
        return String(bytes: bytes[i..<i + length], encoding: .utf8)
    }

    private static func find(_ pattern: [UInt8], in bytes: [UInt8]) -> Int? {
        guard !pattern.isEmpty, bytes.count >= pattern.count else { return nil }
        var i = 0
        let last = bytes.count - pattern.count
        while i <= last {
            if bytes[i] == pattern[0], Array(bytes[i..<i + pattern.count]) == pattern { return i }
            i += 1
        }
        return nil
    }

    // MARK: Hilfen

    /// Bekannte KI-Generatoren anhand ihres Namens in Metadaten.
    static func knownGenerator(in text: String) -> String? {
        let t = text.lowercased()
        let table: [(String, String)] = [
            ("chatgpt", "ChatGPT (OpenAI)"), ("dall-e", "DALL·E (OpenAI)"), ("dall·e", "DALL·E (OpenAI)"),
            ("openai", "OpenAI"), ("sora", "Sora (OpenAI)"),
            ("firefly", "Adobe Firefly"), ("midjourney", "Midjourney"),
            ("stable diffusion", "Stable Diffusion"), ("stability ai", "Stability AI"), ("comfyui", "ComfyUI"),
            ("novelai", "NovelAI"), ("imagen", "Google Imagen"), ("gemini", "Google Gemini"),
            ("bing image creator", "Microsoft Bing Image Creator"), ("microsoft designer", "Microsoft Designer"),
            ("meta ai", "Meta AI"), ("runway", "Runway"), ("leonardo", "Leonardo.Ai"), ("ideogram", "Ideogram"),
            ("flux", "Flux (Black Forest Labs)"), ("grok", "Grok (xAI)"), ("canva ai", "Canva Magic Media"),
        ]
        return table.first { t.contains($0.0) }?.1
    }

    private static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.count > 1200 ? String(trimmed.prefix(1200)) + " …" : trimmed
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }
}
