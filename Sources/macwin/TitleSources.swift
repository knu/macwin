import ApplicationServices
import CoreGraphics
import Foundation
import ScreenCaptureKit

func cgWindowInfo() throws -> [[String: Any]] {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        throw MacWinError(description: "failed to query windows")
    }
    return windows
}

func cgTitleMap() throws -> [CGWindowID: String] {
    try cgWindowInfo().reduce(into: [:]) { titles, info in
        guard let windowID = cgWindowID(info[kCGWindowNumber as String]),
              let title = info[kCGWindowName as String] as? String
        else {
            return
        }
        titles[windowID] = title
    }
}

func scTitleMap() async throws -> [CGWindowID: String] {
    let content = try await SCShareableContent.current
    return content.windows.reduce(into: [:]) { titles, window in
        guard let title = window.title else {
            return
        }
        titles[window.windowID] = title
    }
}

func axTitle(pid: pid_t, windowID: CGWindowID) -> String? {
    let appElement = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
          let axWindows = value as? [AXUIElement],
          let window = axWindows.first(where: { axWindow in
              var currentID = CGWindowID(0)
              return _AXUIElementGetWindow(axWindow, &currentID) == .success && currentID == windowID
          })
    else {
        return nil
    }

    var title: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success else {
        return nil
    }
    return title as? String
}
