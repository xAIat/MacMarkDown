import AppKit

// `macmarkdown` — command-line companion: it records the files (or piped
// stdin) for the app to open on its next launch, then launches the app.

// Must match `Constants.cliHandoffSuiteName` in the app. Using the app's own
// bundle identifier as a suite name is invalid, so a dedicated suite is used.
let suiteName = "com.xaiat.MacMarkDown.cli"
let filesKey = "filesToOpenOnNextLaunch"
let pipedContentKey = "pipedContentFileToOpenOnNextLaunch"
let version = "1.0"

func printUsage() {
    print("""
    Usage: macmarkdown [options] [files...]

    Opens Markdown files in MacMarkDown. With no arguments, reads piped
    standard input into a new document.

    Options:
      -h, --help      Show this help.
      -v, --version   Show the version.
    """)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("-h") || arguments.contains("--help") {
    printUsage()
    exit(0)
}
if arguments.contains("-v") || arguments.contains("--version") {
    print("macmarkdown \(version)")
    exit(0)
}

var files: [String] = []
var pipedContentPath: String?

if arguments.isEmpty {
    guard isatty(STDIN_FILENO) == 0 else {
        printUsage()
        exit(0)
    }
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty else { exit(0) }
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("macmarkdown-stdin-\(UUID().uuidString).md")
    do {
        try data.write(to: temp)
        pipedContentPath = temp.path
    } catch {
        FileHandle.standardError.write(Data("macmarkdown: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
} else {
    files = arguments.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
}

guard let defaults = UserDefaults(suiteName: suiteName) else {
    FileHandle.standardError.write(Data("macmarkdown: cannot access app preferences\n".utf8))
    exit(1)
}
if !files.isEmpty {
    defaults.set(files, forKey: filesKey)
}
if let pipedContentPath {
    defaults.set(pipedContentPath, forKey: pipedContentKey)
}
defaults.synchronize()

// Locate the app bundle: the CLI lives in MacMarkDown.app/Contents/MacOS.
let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let appURL = executableURL
    .deletingLastPathComponent()  // MacOS
    .deletingLastPathComponent()  // Contents
    .deletingLastPathComponent()  // MacMarkDown.app
guard appURL.pathExtension == "app" else {
    FileHandle.standardError.write(Data("macmarkdown: app bundle not found next to the CLI\n".utf8))
    exit(1)
}

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = true
let semaphore = DispatchSemaphore(value: 0)
NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
    if let error {
        FileHandle.standardError.write(Data("macmarkdown: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    semaphore.signal()
}
semaphore.wait()