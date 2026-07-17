import Foundation

enum FinalizerError: Error {
    case missingArgument(String)
}

let arguments = Array(CommandLine.arguments.dropFirst())

func value(after flag: String) throws -> String {
    guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
        throw FinalizerError.missingArgument(flag)
    }
    return arguments[index + 1]
}

func values(after flag: String) -> [String] {
    arguments.indices.compactMap { index in
        guard arguments[index] == flag, arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

let archivePath = try value(after: "--archive")
let typeIdentifier = try value(after: "--type")
let configuration = try value(after: "--configuration")
let triple = try value(after: "--triple")
let board = try value(after: "--board")
let outputPaths = try ["--elf", "--bin", "--uf2"].map(value(after:))
let resourcePaths = values(after: "--resource")

let archive = try Data(contentsOf: URL(fileURLWithPath: archivePath))
let resources = try resourcePaths.map { path in
    try String(contentsOfFile: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
}
let metadata = """
type=\(typeIdentifier)
configuration=\(configuration)
triple=\(triple)
board=\(board)
resources=\(resources.joined(separator: ","))
archive-bytes=\(archive.count)
"""

for (index, outputPath) in outputPaths.enumerated() {
    let outputURL = URL(fileURLWithPath: outputPath)
    var data = Data("format=\(["elf", "bin", "uf2"][index])\n\(metadata)\n".utf8)
    data.append(archive.prefix(64))
    try data.write(to: outputURL)
}

if arguments.contains("--emit-debug-directory") {
    let debugDirectory = URL(fileURLWithPath: try value(after: "--debug-directory"))
    try FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
    try Data(metadata.utf8).write(to: debugDirectory.appendingPathComponent("metadata.txt"))
}
