import Foundation

extension ScreenshotKey: ExpressibleByStringLiteral {
    init(stringLiteral path: String) {
        self.init(asGiven: path)
    }
}

extension URL {
    var screenshotKey: ScreenshotKey { ScreenshotKey(asGiven: self) }
}
