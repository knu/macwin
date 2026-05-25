import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

func initializeWindowServerConnection() {
    _ = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
}

struct CandidateWindow {
    let windowID: CGWindowID
    let pid: pid_t
    let appName: String
    let bundleID: String?
    let title: String?
    let cgTitle: String?
    let scTitle: String?
    let axTitle: String?
    let includeAXTitle: Bool
    let bounds: CGRect
    let isOnScreen: Bool
    let scWindow: SCWindow?
}

func runFind(_ config: FindConfig) async throws -> FindResponse {
    let candidates = try await candidateWindows(config)
    var results: [WindowResult] = []
    let preOCRPredicates = config.predicates.filter { !predicateReferencesOCR($0) }
    let postOCRPredicates = config.predicates.filter(predicateReferencesOCR)

    for candidate in candidates where matches(window: candidate, config: config) {
        let basicResult = windowResult(window: candidate, ocrRegions: nil, tokens: nil)
        guard predicates(preOCRPredicates, match: basicResult) else {
            continue
        }
        guard let result = try await findResult(window: candidate, config: config) else {
            continue
        }
        if !predicates(postOCRPredicates, match: result) {
            continue
        }
        results.append(result)
        if let limit = config.limit, results.count >= limit {
            break
        }
    }

    return FindResponse(windows: results)
}

func predicates(_ predicates: [NSPredicate], match window: WindowResult) -> Bool {
    let object = predicateObject(window: window)
    return predicates.allSatisfy { $0.evaluate(with: object) }
}

func findResult(window: CandidateWindow, config: FindConfig) async throws -> WindowResult? {
    guard config.ocr else {
        return windowResult(window: window, ocrRegions: nil, tokens: nil)
    }
    guard let scWindow = window.scWindow else {
        return nil
    }

    let image = try await capture(window: scWindow)
    var resolvedRegions: [OCRRegion] = []
    var allTokens: [OCRToken] = []
    for region in config.ocrRegions {
        let rect = resolve(rect: region.rect, in: window.bounds)
        guard rect.width > 0, rect.height > 0 else {
            throw MacWinError(description: "resolved --ocr range is empty")
        }
        let cropped = try crop(image: image, rect: rect.cgRect, windowFrame: window.bounds)
        if let saveImage = region.saveImage {
            try save(image: cropped, to: saveImage, workingDirectory: config.workingDirectory)
        }
        let tokens = try recognizeText(
            in: cropped,
            cropRect: rect,
            name: region.name,
            languages: config.languages,
            minConfidence: config.minConfidence
        )
        resolvedRegions.append(OCRRegion(name: region.name, saveImage: region.saveImage, rect: rect))
        allTokens.append(contentsOf: tokens)
    }
    return windowResult(window: window, ocrRegions: resolvedRegions, tokens: allTokens)
}

func resolve(rect: Rect, in windowBounds: CGRect) -> Rect {
    let originX = resolveOrigin(rect.originX, length: windowBounds.width)
    let originY = resolveOrigin(rect.originY, length: windowBounds.height)
    let width = resolveLength(rect.width, origin: originX, length: windowBounds.width)
    let height = resolveLength(rect.height, origin: originY, length: windowBounds.height)
    return Rect(originX: originX, originY: originY, width: width, height: height)
}

func resolveOrigin(_ value: Double, length: Double) -> Double {
    value < 0 ? length + value : value
}

func resolveLength(_ value: Double, origin: Double, length: Double) -> Double {
    if value == 0 {
        return length - origin
    }
    if value < 0 {
        return length - origin + value
    }
    return value
}

func candidateWindows(_ config: FindConfig) async throws -> [CandidateWindow] {
    if config.ocr {
        let content = try await SCShareableContent.current
        let cgTitles = try cgTitleMap()
        return content.windows.compactMap { window in
            guard let app = window.owningApplication else {
                return nil
            }
            let cgTitle = cgTitles[window.windowID].nonEmpty
            let scTitle = window.title.nonEmpty
            return CandidateWindow(
                windowID: window.windowID,
                pid: app.processID,
                appName: app.applicationName,
                bundleID: app.bundleIdentifier,
                title: cgTitle ?? scTitle,
                cgTitle: cgTitle,
                scTitle: scTitle,
                axTitle: config.includeAXTitle ? axTitle(pid: app.processID, windowID: window.windowID) : nil,
                includeAXTitle: config.includeAXTitle,
                bounds: window.frame,
                isOnScreen: window.isOnScreen,
                scWindow: window
            )
        }
    }

    let windows = try cgWindowInfo()
    let candidates = windows.compactMap { candidateWindow($0, scTitles: [:], includeAXTitle: config.includeAXTitle) }
    let needsSCTitles = candidates.contains { candidate in
        candidate.title == nil && preliminaryMatches(window: candidate, config: config)
    }
    guard needsSCTitles else {
        return candidates
    }
    let scTitles = try await scTitleMap()
    return windows.compactMap { candidateWindow($0, scTitles: scTitles, includeAXTitle: config.includeAXTitle) }
}

func candidateWindow(_ info: [String: Any], scTitles: [CGWindowID: String], includeAXTitle: Bool) -> CandidateWindow? {
    guard let windowID = cgWindowID(info[kCGWindowNumber as String]),
          let pid = processID(info[kCGWindowOwnerPID as String]),
          let appName = info[kCGWindowOwnerName as String] as? String,
          let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: boundsInfo)
    else {
        return nil
    }
    let app = NSRunningApplication(processIdentifier: pid)
    let cgTitle = (info[kCGWindowName as String] as? String).nonEmpty
    let scTitle = scTitles[windowID].nonEmpty
    return CandidateWindow(
        windowID: windowID,
        pid: pid,
        appName: appName,
        bundleID: app?.bundleIdentifier,
        title: cgTitle ?? scTitle,
        cgTitle: cgTitle,
        scTitle: scTitle,
        axTitle: includeAXTitle ? axTitle(pid: pid, windowID: windowID) : nil,
        includeAXTitle: includeAXTitle,
        bounds: bounds,
        isOnScreen: boolValue(info[kCGWindowIsOnscreen as String]),
        scWindow: nil
    )
}

func cgWindowID(_ value: Any?) -> CGWindowID? {
    if let value = value as? CGWindowID {
        return value
    }
    if let value = value as? NSNumber {
        return CGWindowID(value.uint32Value)
    }
    return nil
}

func processID(_ value: Any?) -> pid_t? {
    if let value = value as? pid_t {
        return value
    }
    if let value = value as? NSNumber {
        return value.int32Value
    }
    return nil
}

func boolValue(_ value: Any?) -> Bool {
    if let value = value as? Bool {
        return value
    }
    if let value = value as? NSNumber {
        return value.boolValue
    }
    return false
}

func raiseWindows(_ windows: [WindowResult]) throws {
    for window in windows {
        try raiseWindow(windowID: window.windowID)
    }
}

func matches(window: CandidateWindow, config: FindConfig) -> Bool {
    guard preliminaryMatches(window: window, config: config) else {
        return false
    }
    if let titleRegex = config.titleRegex {
        guard let title = window.title, title.firstMatch(of: titleRegex) != nil else {
            return false
        }
    }
    return true
}

func preliminaryMatches(window: CandidateWindow, config: FindConfig) -> Bool {
    guard window.windowID != 0, window.bounds.width > 0, window.bounds.height > 0 else {
        return false
    }
    if !config.includeOffscreen, !window.isOnScreen {
        return false
    }
    if let windowID = config.windowID, window.windowID != windowID {
        return false
    }
    if let appName = config.appName, window.appName != appName {
        return false
    }
    if let bundleID = config.bundleID, window.bundleID != bundleID {
        return false
    }
    return true
}

func windowResult(window: CandidateWindow, ocrRegions: [OCRRegion]?, tokens: [OCRToken]?) -> WindowResult {
    WindowResult(
        windowID: window.windowID,
        pid: window.pid,
        appName: window.appName,
        bundleID: window.bundleID,
        title: window.title,
        axTitle: window.axTitle,
        includeAXTitle: window.includeAXTitle,
        bounds: Rect(window.bounds),
        ocrRect: ocrRegions?.count == 1 ? ocrRegions?.first?.rect : nil,
        ocrRegions: ocrRegions,
        ocr: tokens
    )
}

func predicateObject(window: WindowResult) -> [String: Any] {
    var object: [String: Any] = [
        "window_id": window.windowID,
        "pid": window.pid,
        "app_name": window.appName,
        "bounds": predicateObject(rect: window.bounds)
    ]
    if let bundleID = window.bundleID {
        object["bundle_id"] = bundleID
    }
    if let title = window.title {
        object["title"] = title
    }
    if let axTitle = window.axTitle {
        object["ax_title"] = axTitle
    }
    if let ocrRect = window.ocrRect {
        object["ocr_rect"] = predicateObject(rect: ocrRect)
    }
    if let ocrRegions = window.ocrRegions {
        object["ocr_regions"] = ocrRegions.map(predicateObject(region:))
    }
    if let ocr = window.ocr {
        object["ocr"] = ocr.map(predicateObject(token:))
    }
    return object
}

func predicateObject(rect: Rect) -> [String: Any] {
    [
        "x": rect.originX,
        "y": rect.originY,
        "w": rect.width,
        "h": rect.height
    ]
}

func predicateObject(region: OCRRegion) -> [String: Any] {
    var object: [String: Any] = [
        "rect": predicateObject(rect: region.rect)
    ]
    if let name = region.name {
        object["name"] = name
    }
    if let saveImage = region.saveImage {
        object["save_image"] = saveImage
    }
    return object
}

func predicateObject(token: OCRToken) -> [String: Any] {
    var object: [String: Any] = [
        "text": token.text,
        "confidence": token.confidence,
        "bbox": predicateObject(rect: token.bbox)
    ]
    if let name = token.name {
        object["name"] = name
    }
    return object
}

func capture(window: SCWindow) async throws -> CGImage {
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = SCStreamConfiguration()
    configuration.width = max(1, Int(window.frame.width.rounded()))
    configuration.height = max(1, Int(window.frame.height.rounded()))
    configuration.showsCursor = false
    configuration.backgroundColor = CGColor.clear
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
}

func crop(image: CGImage, rect: CGRect, windowFrame: CGRect) throws -> CGImage {
    let scaleX = Double(image.width) / max(windowFrame.width, 1)
    let scaleY = Double(image.height) / max(windowFrame.height, 1)
    let pixelRect = CGRect(
        x: rect.origin.x * scaleX,
        y: rect.origin.y * scaleY,
        width: rect.width * scaleX,
        height: rect.height * scaleY
    ).integral
    let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let clipped = pixelRect.intersection(imageBounds)

    guard !clipped.isNull, let cropped = image.cropping(to: clipped) else {
        throw MacWinError(description: "--ocr rect is outside the captured window")
    }
    return cropped
}

func save(image: CGImage, to path: String, workingDirectory: String) throws {
    let url = fileURL(path: path, workingDirectory: workingDirectory)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let imageType = UTType.png.identifier as CFString
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, imageType, 1, nil) else {
        throw MacWinError(description: "failed to create image destination: \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw MacWinError(description: "failed to save image: \(url.path)")
    }
}

func fileURL(path: String, workingDirectory: String) -> URL {
    path.hasPrefix("/")
        ? URL(fileURLWithPath: path)
        : URL(fileURLWithPath: workingDirectory).appendingPathComponent(path)
}
