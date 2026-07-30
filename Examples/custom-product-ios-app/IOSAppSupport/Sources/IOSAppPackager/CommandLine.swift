import Foundation

struct PackagerArguments {
    let payloadJSON: String
    let aggregateArchive: URL
    let targetTriple: String
    let platform: PackagerPlatform
    let configuration: String
    let resourceFiles: [URL]
    let outputArchive: URL?
    let outputIPA: URL?
    let outputApp: URL?
    let outputReport: URL

    init(_ arguments: [String] = Array(CommandLine.arguments.dropFirst())) throws {
        func required(_ flag: String) throws -> String {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                throw PackagerError("missing required argument \(flag)")
            }
            return arguments[index + 1]
        }

        func repeated(_ flag: String) -> [String] {
            arguments.indices.compactMap { index in
                guard arguments[index] == flag, arguments.indices.contains(index + 1) else { return nil }
                return arguments[index + 1]
            }
        }

        func optional(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                return nil
            }
            return arguments[index + 1]
        }

        payloadJSON = try required("--payload-json")
        aggregateArchive = URL(fileURLWithPath: try required("--aggregate-archive"))
        targetTriple = try required("--target-triple")
        let platformValue = try required("--platform")
        guard let platform = PackagerPlatform(rawValue: platformValue) else {
            throw PackagerError("--platform must be device or simulator, received \(platformValue)")
        }
        self.platform = platform
        configuration = try required("--configuration")
        resourceFiles = repeated("--resource-file").map(URL.init(fileURLWithPath:))
        outputArchive = optional("--output-archive").map(URL.init(fileURLWithPath:))
        outputIPA = optional("--output-ipa").map(URL.init(fileURLWithPath:))
        outputApp = optional("--output-app").map(URL.init(fileURLWithPath:))
        outputReport = URL(fileURLWithPath: try required("--output-report"))

        switch platform {
        case .device:
            guard outputArchive != nil, outputIPA != nil, outputApp == nil else {
                throw PackagerError("device packaging requires --output-archive and --output-ipa only")
            }
        case .simulator:
            guard outputArchive == nil, outputIPA == nil, outputApp != nil else {
                throw PackagerError("simulator packaging requires --output-app only")
            }
        }
    }
}

enum PackagerPlatform: String, Codable {
    case device
    case simulator

    var sdkRoot: String {
        switch self {
        case .device: "iphoneos"
        case .simulator: "iphonesimulator"
        }
    }

    var supportedPlatforms: String { sdkRoot }
}

struct PackagerError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

struct ProcessRunner {
    private(set) var commands: [[String]] = []

    mutating func run(_ executable: URL, _ arguments: [String], currentDirectory: URL? = nil) throws {
        let command = [executable.path] + arguments
        commands.append(command)
        print("[IOSAppPackager] \(command.map(Self.shellQuoted).joined(separator: " "))")

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw PackagerError("command failed with status \(process.terminationStatus): \(command.joined(separator: " "))")
        }
    }

    private static func shellQuoted(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || "'\"\\$`".contains($0) }) else { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum ToolLocator {
    static func xcodegen(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let candidates = [
            environment["XCODEGEN"],
            "/opt/homebrew/bin/xcodegen",
            "/usr/local/bin/xcodegen",
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        throw PackagerError("xcodegen was not found; install it with 'brew install xcodegen' or set XCODEGEN")
    }

    static let xcodebuild = URL(fileURLWithPath: "/usr/bin/xcodebuild")
    static let zip = URL(fileURLWithPath: "/usr/bin/zip")
    static let codesign = URL(fileURLWithPath: "/usr/bin/codesign")
}
