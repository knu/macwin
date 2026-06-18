import CoreGraphics
import Foundation

// swiftlint:disable:next cyclomatic_complexity
func parseFind(_ arguments: [String]) throws -> FindConfig {
    var config = FindConfig()
    var parser = ArgumentParser(arguments)

    while let argument = parser.next() {
        switch argument {
        case "--app":
            config.appName = try parser.value(for: argument)
        case "--bundle-id":
            config.bundleID = try parser.value(for: argument)
        case "--title-regex":
            config.titleRegex = try Regex(parser.value(for: argument))
        case "--where":
            config.predicates.append(NSPredicate(format: try parser.value(for: argument)))
        case "--window-id":
            config.windowID = try CGWindowID(parseUInt32(parser.value(for: argument), name: argument))
        case "--ocr":
            config.ocr = true
            config.ocrRegions.append(try parseOCRRegion(parser.value(for: argument), name: argument))
        case "--lang":
            config.languages = try parseLanguages(parser.value(for: argument))
        case "--min-confidence":
            guard let value = try Float(parser.value(for: argument)) else {
                throw MacWinError(description: "invalid value for \(argument)")
            }
            config.minConfidence = value
        case "--limit":
            config.limit = try parseLimit(parser.value(for: argument))
        case "--wait":
            config.wait = try parseWait(parser.value(for: argument))
        case "--exit-status":
            config.exitStatus = true
        case "--raise":
            config.raise = true
        case "--close":
            config.close = true
        case "--include-offscreen":
            config.includeOffscreen = true
        case "--ax":
            config.includeAXTitle = true
        case "--pretty":
            config.pretty = true
        default:
            throw MacWinError(description: "unknown find option: \(argument)")
        }
    }

    if !config.ocr, config.predicates.contains(where: predicateReferencesOCR) {
        throw MacWinError(description: "--ocr X,Y,W,H[;name=NAME] is required when --where references ocr")
    }
    if config.raise, config.close {
        throw MacWinError(description: "--raise and --close are mutually exclusive")
    }
    if config.appName == nil, config.bundleID == nil, config.windowID == nil {
        throw MacWinError(description: "one of --app, --bundle-id, or --window-id is required")
    }

    return config
}

func predicateReferencesOCR(_ predicate: NSPredicate) -> Bool {
    predicate.predicateFormat.range(of: #"\bocr\b"#, options: .regularExpression) != nil
}

func parseWindowIDCommand(_ arguments: [String], commandName: String) throws -> CGWindowID {
    var parser = ArgumentParser(arguments)
    var windowID: CGWindowID?

    while let argument = parser.next() {
        switch argument {
        case "--window-id":
            windowID = try CGWindowID(parseUInt32(parser.value(for: argument), name: argument))
        default:
            throw MacWinError(description: "unknown \(commandName) option: \(argument)")
        }
    }

    guard let windowID else {
        throw MacWinError(description: "--window-id is required")
    }
    return windowID
}

struct ArgumentParser {
    private var arguments: [String]

    init(_ arguments: [String]) {
        self.arguments = arguments
    }

    mutating func next() -> String? {
        guard !arguments.isEmpty else {
            return nil
        }
        return arguments.removeFirst()
    }

    mutating func value(for option: String) throws -> String {
        guard let value = next(), !value.hasPrefix("--") else {
            throw MacWinError(description: "\(option) requires a value")
        }
        return value
    }
}

func parseUInt32(_ value: String, name: String) throws -> UInt32 {
    guard let parsed = UInt32(value) else {
        throw MacWinError(description: "invalid value for \(name)")
    }
    return parsed
}

func parseLimit(_ value: String) throws -> Int {
    guard let limit = Int(value), limit > 0 else {
        throw MacWinError(description: "invalid value for --limit")
    }
    return limit
}

func parseWait(_ value: String) throws -> Double {
    guard let seconds = Double(value), seconds >= 0, seconds.isFinite else {
        throw MacWinError(description: "invalid value for --wait")
    }
    return seconds
}

func parseOCRRegion(_ value: String, name: String) throws -> OCRRegion {
    let fields = value.split(separator: ";", omittingEmptySubsequences: false)
    guard let rectField = fields.first else {
        throw MacWinError(description: "\(name) must be X,Y,W,H[;name=NAME]")
    }
    let rect = try parseRect(String(rectField), name: name)
    let attributes = try parseOCRRegionAttributes(fields.dropFirst(), option: name)
    return OCRRegion(name: attributes.name, saveImage: attributes.saveImage, rect: rect)
}

typealias OCRRegionAttributes = (name: String?, saveImage: String?)

func parseOCRRegionAttributes(_ fields: ArraySlice<Substring>, option: String) throws -> OCRRegionAttributes {
    var regionName: String?
    var saveImage: String?
    for field in fields {
        let parts = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw MacWinError(description: "invalid \(option) attribute: \(field)")
        }
        switch parts[0] {
        case "name":
            regionName = String(parts[1])
        case "save_image":
            saveImage = String(parts[1])
        default:
            throw MacWinError(description: "invalid \(option) attribute: \(field)")
        }
    }
    return (regionName, saveImage)
}

func parseRect(_ value: String, name: String) throws -> Rect {
    let parts = value.split(separator: ",", omittingEmptySubsequences: false)
    guard parts.count == 4 else {
        throw MacWinError(description: "\(name) must be X,Y,W,H[;name=NAME]")
    }
    let numbers = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard numbers.count == 4 else {
        throw MacWinError(description: "invalid value for \(name)")
    }
    return Rect(originX: numbers[0], originY: numbers[1], width: numbers[2], height: numbers[3])
}

func parseLanguages(_ value: String) -> [String] {
    value
        .split(separator: ",")
        .map { language in
            let code = String(language)
            if code.contains("-") {
                return code
            }
            return Locale(identifier: code).identifier.replacingOccurrences(of: "_", with: "-")
        }
}
