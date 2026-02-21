import Foundation

struct FormatDetector {
    static func detect(formatHint: FormatHint, inputFile: URL?) -> ResolvedFormat {
        switch formatHint {
        case .text:
            return .text
        case .markdown:
            return .markdown
        case .html:
            return .html
        case .auto:
            guard let file = inputFile else {
                return .text
            }
            let ext = file.pathExtension.lowercased()
            switch ext {
            case "md", "markdown", "mdx":
                return .markdown
            case "html", "htm":
                return .html
            default:
                return .text
            }
        }
    }
}
