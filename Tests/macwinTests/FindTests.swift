import CoreGraphics
import Foundation
@testable import macwin
import XCTest

final class FindTests: XCTestCase {
    let finderTestPrefix = "macwin-finder-test-"

    func testCandidateWindowKeepsCGTitleWhenAXRequested() throws {
        let title = "Work Dashboard"
        let window = try XCTUnwrap(candidateWindow(
            [
                kCGWindowNumber as String: NSNumber(value: 123),
                kCGWindowOwnerPID as String: NSNumber(value: getpid()),
                kCGWindowOwnerName as String: "Finder",
                kCGWindowName as String: title,
                kCGWindowBounds as String: [
                    "X": 0,
                    "Y": 0,
                    "Width": 800,
                    "Height": 600
                ],
                kCGWindowIsOnscreen as String: true
            ],
            scTitles: [:],
            includeAXTitle: true
        ))

        XCTAssertEqual(window.title, title)
    }

    func testPredicateCanMatchTitleWhenAXTitleIsDifferent() throws {
        let title = "Work Dashboard"
        let result = WindowResult(
            windowID: 123,
            pid: getpid(),
            appName: "Finder",
            bundleID: "com.apple.finder",
            title: title,
            axTitle: "Different Accessibility Title",
            includeAXTitle: true,
            bounds: Rect(originX: 0, originY: 0, width: 800, height: 600),
            ocrRect: nil,
            ocrRegions: nil,
            ocr: nil
        )

        let config = try parseFind(["--app", "Finder", "--where", #"title == "Work Dashboard""#, "--ax"])

        XCTAssertTrue(predicates(config.predicates, match: result))
    }

    func testRaiseAndCloseAreMutuallyExclusive() {
        XCTAssertThrowsError(try parseFind(["--app", "Finder", "--raise", "--close"])) { error in
            XCTAssertEqual(String(describing: error), "--raise and --close are mutually exclusive")
        }
    }

    func testFindsPredictableFinderWindow() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["MACWIN_RUN_GUI_TESTS"] == "1" else {
            throw XCTSkip("set MACWIN_RUN_GUI_TESTS=1 to run Finder integration tests")
        }
        guard environment["GITHUB_ACTIONS"] != "true" else {
            throw XCTSkip("Finder integration tests need a logged-in GUI session and TCC permissions")
        }

        closeFinderWindows(containing: finderTestPrefix)

        let directoryName = "\(finderTestPrefix)\(UUID().uuidString)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
        let titleSuffix = "/\(directoryName)"
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer {
            closeFinderWindows(containing: finderTestPrefix)
            try? FileManager.default.removeItem(at: url)
        }

        try runProcess("/usr/bin/open", arguments: [url.path])
        initializeWindowServerConnection()
        let config = try parseFind([
            "--app", "Finder",
            "--where", "title ENDSWITH \"\(predicateString(titleSuffix))\"",
            "--wait", "5",
            "--limit", "1"
        ])
        let response = try await runFindWithWait(config)

        XCTAssertEqual(response.windows.count, 1)
        XCTAssertTrue(response.windows.first?.title?.hasSuffix(titleSuffix) == true)
    }
}

func runProcess(_ executable: String, arguments: [String], timeout: TimeInterval = 5) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    try process.run()
    guard process.waitUntilExit(timeout: timeout) else {
        process.terminate()
        _ = process.waitUntilExit(timeout: 1)
        throw MacWinError(description: "\(executable) timed out")
    }

    guard process.terminationStatus == 0 else {
        throw MacWinError(description: "\(executable) exited with status \(process.terminationStatus)")
    }
}

func closeFinderWindows(containing titleFragment: String) {
    guard let windows = try? cgWindowInfo() else {
        return
    }

    for info in windows {
        guard let windowID = cgWindowID(info[kCGWindowNumber as String]),
              info[kCGWindowOwnerName as String] as? String == "Finder",
              let title = info[kCGWindowName as String] as? String,
              title.contains(titleFragment)
        else {
            continue
        }
        try? closeWindows([
            WindowResult(
                windowID: windowID,
                pid: 0,
                appName: "Finder",
                bundleID: "com.apple.finder",
                title: title,
                axTitle: nil,
                includeAXTitle: false,
                bounds: Rect(originX: 0, originY: 0, width: 1, height: 1),
                ocrRect: nil,
                ocrRegions: nil,
                ocr: nil
            )
        ])
    }
}

func predicateString(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

extension Process {
    func waitUntilExit(timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        terminationHandler = { _ in
            semaphore.signal()
        }

        if !isRunning {
            return true
        }
        let result = semaphore.wait(timeout: .now() + timeout)
        return result == .success
    }
}
