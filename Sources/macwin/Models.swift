import CoreGraphics
import Foundation

struct MacWinError: Error, CustomStringConvertible {
    let description: String
}

struct Rect: Codable {
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double

    enum CodingKeys: String, CodingKey {
        case originX = "x"
        case originY = "y"
        case width = "w"
        case height = "h"
    }

    var cgRect: CGRect {
        CGRect(x: originX, y: originY, width: width, height: height)
    }

    init(_ rect: CGRect) {
        originX = rect.origin.x
        originY = rect.origin.y
        width = rect.width
        height = rect.height
    }

    init(originX: Double, originY: Double, width: Double, height: Double) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }
}

struct OCRToken: Codable {
    let name: String?
    let text: String
    let confidence: Float
    let bbox: Rect
}

struct OCRRegion: Codable {
    let name: String?
    let saveImage: String?
    let rect: Rect

    enum CodingKeys: String, CodingKey {
        case name
        case saveImage = "save_image"
        case rect
    }
}

struct WindowResult: Encodable {
    let windowID: CGWindowID
    let pid: pid_t
    let appName: String
    let bundleID: String?
    let title: String?
    let axTitle: String?
    let includeAXTitle: Bool
    let bounds: Rect
    let ocrRect: Rect?
    let ocrRegions: [OCRRegion]?
    let ocr: [OCRToken]?

    enum CodingKeys: String, CodingKey {
        case windowID = "window_id"
        case pid
        case appName = "app_name"
        case bundleID = "bundle_id"
        case title
        case axTitle = "ax_title"
        case bounds
        case ocrRect = "ocr_rect"
        case ocrRegions = "ocr_regions"
        case ocr
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windowID, forKey: .windowID)
        try container.encode(pid, forKey: .pid)
        try container.encode(appName, forKey: .appName)
        try container.encodeIfPresent(bundleID, forKey: .bundleID)
        try container.encode(title, forKey: .title)
        if includeAXTitle {
            try container.encode(axTitle, forKey: .axTitle)
        }
        try container.encode(bounds, forKey: .bounds)
        try container.encodeIfPresent(ocrRect, forKey: .ocrRect)
        try container.encodeIfPresent(ocrRegions, forKey: .ocrRegions)
        try container.encodeIfPresent(ocr, forKey: .ocr)
    }
}

struct FindResponse: Encodable {
    let windows: [WindowResult]
}

struct FindConfig {
    var appName: String?
    var bundleID: String?
    var titleRegex: Regex<Substring>?
    var predicates: [NSPredicate] = []
    var windowID: CGWindowID?
    var ocrRegions: [OCRRegion] = []
    var languages = ["ja-JP", "en-US"]
    var minConfidence: Float = 0
    var includeOffscreen = false
    var pretty = false
    var limit: Int?
    var exitStatus = false
    var raise = false
    var ocr = false
    var includeAXTitle = false
    var wait: Double?
    var workingDirectory = FileManager.default.currentDirectoryPath

    var hasWaitableCondition: Bool {
        titleRegex != nil || !predicates.isEmpty || limit != nil
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? {
        guard let value = self, !value.isEmpty else {
            return nil
        }
        return value
    }
}
