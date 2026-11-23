import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The figures' pictures, read from the project and carried in the page as data URLs, so the page fetches nothing. A
/// picture WebKit may not draw (HEIC, TIFF) is carried as PNG.
struct QuillPictures {
    struct Picture {
        let url: URL
        let data: Data
        /// png, jpeg or gif.
        let type: String
        let width: Int
        let height: Int
        var dataURL: String { "data:image/\(type);base64,\(data.base64EncodedString())" }
    }

    /// By block index.
    let pictures: [Int: Picture]
    /// Figures whose picture is not there or is not a picture, by block index.
    let missing: [Int]

    static func read(_ document: QuillDocument, in folder: URL) -> QuillPictures {
        var found: [Int: Picture] = [:]
        var missing: [Int] = []
        for (index, block) in document.blocks.enumerated() where block.kind == .figure {
            guard let path = block.path, let picture = picture(at: url(path, in: folder)) else { missing.append(index); continue }
            found[index] = picture
        }
        return QuillPictures(pictures: found, missing: missing)
    }

    static func url(_ path: String, in folder: URL) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : folder.appendingPathComponent(expanded)
    }

    static func picture(at url: URL) -> Picture? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let kind = CGImageSourceGetType(source) as String? else { return nil }
        let direct: [String: String] = [UTType.png.identifier: "png", UTType.jpeg.identifier: "jpeg", UTType.gif.identifier: "gif"]
        if let type = direct[kind], let data = try? Data(contentsOf: url) {
            return Picture(url: url, data: data, type: type, width: width, height: height)
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return Picture(url: url, data: out as Data, type: "png", width: width, height: height)
    }

    var dataURLs: [Int: String] { pictures.mapValues(\.dataURL) }
}
