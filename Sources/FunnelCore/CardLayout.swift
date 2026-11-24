import Foundation

public struct CardLayout {
    public static let spacing: CGFloat = 24
    public static let inset: CGFloat = 7
    public let previews: [CGSize]
    public let centers: [CGFloat]

    public static let maximumPreviewSize = CGSize(width: 960 - 2 * inset, height: 610 - 47)

    public init(sources: [CGSize], viewport: CGSize, limitToSourceSize: Bool = false) {
        let widthLimit = max(1, min(Self.maximumPreviewSize.width, viewport.width * 0.64 - 2 * Self.inset))
        let heightLimit = max(1, min(Self.maximumPreviewSize.height, viewport.height * 0.64 - 47))
        previews = sources.map { size in
            let ratio = size.width > 0 && size.height > 0 ? size.width / size.height : 1.6
            let height = min(heightLimit, widthLimit / ratio, limitToSourceSize && size.height > 0 ? size.height : heightLimit)
            return CGSize(width: height * ratio, height: height)
        }
        var left: CGFloat = 0
        centers = previews.map { preview in
            let width = preview.width + 2 * Self.inset
            defer { left += width + Self.spacing }
            return left + width / 2
        }
    }
}
