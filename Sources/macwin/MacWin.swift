import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

@main
enum MacWin {
    static func main() async {
        var streams = StandardStreams(stdoutPath: nil, stderrPath: nil, statusPath: nil, cwdPath: nil)
        var exitCode: Int32 = 0

        do {
            var arguments = Array(CommandLine.arguments.dropFirst())
            streams = try parseStandardStreams(&arguments)
            try redirectStandardStreams(streams)

            guard let command = arguments.first else {
                printUsage()
                throw MacWinError(description: "missing subcommand")
            }
            arguments.removeFirst()

            switch command {
            case "find":
                initializeWindowServerConnection()
                var config = try parseFind(arguments)
                config.workingDirectory = streams.cwdPath ?? FileManager.default.currentDirectoryPath
                let response = try await runFind(config)
                try writeJSON(response, pretty: config.pretty)
                if config.raise {
                    try raiseWindows(response.windows)
                }
                if config.exitStatus, response.windows.isEmpty {
                    exitCode = 1
                }
            case "raise":
                initializeWindowServerConnection()
                let windowID = try parseWindowIDCommand(arguments, commandName: command)
                try raiseWindow(windowID: windowID)
            case "close":
                initializeWindowServerConnection()
                let windowID = try parseWindowIDCommand(arguments, commandName: command)
                try closeWindow(windowID: windowID)
            case "-h", "--help", "help":
                printUsage()
            default:
                printUsage()
                throw MacWinError(description: "unknown subcommand: \(command)")
            }
            writeStatus(exitCode, streams: streams)
            if exitCode != 0 {
                Foundation.exit(exitCode)
            }
        } catch {
            fputs("macwin: \(error)\n", stderr)
            writeStatus(1, streams: streams)
            Foundation.exit(1)
        }
    }

    static func printUsage() {
        print(
            """
            Usage:
              macwin [--stdout=PATH] [--stderr=PATH] [--status=PATH] <subcommand> [options]
              macwin find (--app NAME | --bundle-id ID | --window-id ID) [options]
              macwin raise --window-id ID
              macwin close --window-id ID

            Find options:
              --title-regex REGEX
              --ocr X,Y,W,H[;name=NAME][;save_image=PATH]  (repeatable)
              --where NSPREDICATE  (repeatable, AND)
              --lang ja,en
              --min-confidence VALUE
              --limit COUNT
              --exit-status
              --raise
              --include-offscreen
              --ax
              --pretty
            """
        )
    }
}

struct StandardStreams {
    let stdoutPath: String?
    let stderrPath: String?
    let statusPath: String?
    let cwdPath: String?
}

func parseStandardStreams(_ arguments: inout [String]) throws -> StandardStreams {
    var stdoutPath: String?
    var stderrPath: String?
    var statusPath: String?
    var cwdPath: String?
    var remaining: [String] = []
    var parser = ArgumentParser(arguments)

    while let argument = parser.next() {
        if argument == "--stdout" {
            stdoutPath = try parser.value(for: argument)
        } else if argument == "--stderr" {
            stderrPath = try parser.value(for: argument)
        } else if argument == "--status" {
            statusPath = try parser.value(for: argument)
        } else if argument == "--cwd" {
            cwdPath = try parser.value(for: argument)
        } else if let value = argument.droppingPrefix("--stdout=") {
            stdoutPath = value
        } else if let value = argument.droppingPrefix("--stderr=") {
            stderrPath = value
        } else if let value = argument.droppingPrefix("--status=") {
            statusPath = value
        } else if let value = argument.droppingPrefix("--cwd=") {
            cwdPath = value
        } else {
            remaining.append(argument)
        }
    }

    arguments = remaining
    return StandardStreams(stdoutPath: stdoutPath, stderrPath: stderrPath, statusPath: statusPath, cwdPath: cwdPath)
}

func redirectStandardStreams(_ streams: StandardStreams) throws {
    if let stdoutPath = streams.stdoutPath {
        try redirect(path: stdoutPath, to: STDOUT_FILENO)
    }
    if let stderrPath = streams.stderrPath {
        try redirect(path: stderrPath, to: STDERR_FILENO)
    }
}

func writeStatus(_ status: Int32, streams: StandardStreams) {
    guard let statusPath = streams.statusPath else {
        return
    }
    let data = Data("\(status)\n".utf8)
    try? data.write(to: URL(fileURLWithPath: statusPath))
}

func redirect(path: String, to target: Int32) throws {
    let descriptor = open(path, O_WRONLY)
    guard descriptor >= 0 else {
        throw MacWinError(description: "failed to open \(path): \(String(cString: strerror(errno)))")
    }
    defer {
        close(descriptor)
    }

    guard dup2(descriptor, target) >= 0 else {
        throw MacWinError(description: "failed to redirect fd \(target): \(String(cString: strerror(errno)))")
    }
}

func raiseWindow(windowID: CGWindowID) throws {
    let target = try axWindow(windowID: windowID)
    let raiseError = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
    guard raiseError == .success else {
        throw MacWinError(description: "failed to raise window \(windowID): \(raiseError.rawValue)")
    }

    AXUIElementSetAttributeValue(target.element, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
}

func closeWindow(windowID: CGWindowID) throws {
    let target = try axWindow(windowID: windowID)
    var value: CFTypeRef?
    let copyError = AXUIElementCopyAttributeValue(target.element, kAXCloseButtonAttribute as CFString, &value)
    guard copyError == .success, let value else {
        throw MacWinError(description: "cannot access close button for window \(windowID): \(copyError.rawValue)")
    }
    let closeButton = unsafeDowncast(value, to: AXUIElement.self)

    let pressError = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
    guard pressError == .success else {
        throw MacWinError(description: "failed to close window \(windowID): \(pressError.rawValue)")
    }
}

typealias AXWindowTarget = (pid: pid_t, element: AXUIElement)

func axWindow(windowID: CGWindowID) throws -> AXWindowTarget {
    let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        throw MacWinError(description: "failed to query windows")
    }
    guard let info = windows.first(where: { cgWindowID($0[kCGWindowNumber as String]) == windowID }),
          let pid = processID(info[kCGWindowOwnerPID as String])
    else {
        throw MacWinError(description: "window not found: \(windowID)")
    }

    let appElement = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    let copyError = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
    guard copyError == .success, let axWindows = value as? [AXUIElement] else {
        throw MacWinError(description: "cannot access windows for pid \(pid); grant Accessibility permission")
    }

    guard let target = axWindows.first(where: { axWindow in
        var currentID = CGWindowID(0)
        return _AXUIElementGetWindow(axWindow, &currentID) == .success && currentID == windowID
    }) else {
        throw MacWinError(description: "AX window not found: \(windowID)")
    }

    return (pid, target)
}

func writeJSON<T: Encodable>(_ value: T, pretty: Bool) throws {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .useDefaultKeys
    if pretty {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }
    let data = try encoder.encode(value)
    let output = data + Data("\n".utf8)
    FileHandle.standardOutput.write(output)
}

extension String {
    func droppingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}
