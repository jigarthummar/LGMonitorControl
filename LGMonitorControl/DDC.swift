import Foundation

enum DDCError: Error, LocalizedError {
    case binaryMissing
    case nonZeroExit(code: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "m1ddc not found at /opt/homebrew/bin/m1ddc"
        case .nonZeroExit(let code, let stderr):
            return "m1ddc exited \(code): \(stderr)"
        }
    }
}

struct Display: Identifiable, Hashable, Sendable {
    let uuid: String
    let productName: String
    let manufacturer: String   // PNP ID, e.g. "GSM" (LG), "DEL" (Dell), "SAM" (Samsung)
    var id: String { uuid }
}

actor DDC {
    static let shared = DDC()
    static let binaryPath = "/opt/homebrew/bin/m1ddc"

    private var cachedDisplays: [Display]?

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath)
    }

    func invalidate() { cachedDisplays = nil }

    func listDisplays() async throws -> [Display] {
        if let cached = cachedDisplays { return cached }
        let listing = try await Self.runRaw(["display", "list", "detailed"])
        let parsed = Self.parseDisplayList(listing)
        cachedDisplays = parsed
        return parsed
    }

    /// Parses `m1ddc display list detailed` output. Skips built-in / unsupported
    /// displays (Apple's manufacturer code "00-10-fa" or null product name).
    static func parseDisplayList(_ raw: String) -> [Display] {
        var results: [Display] = []
        var currentUUID: String?
        var currentName: String?
        var currentManufacturer: String?

        func flush() {
            defer {
                currentUUID = nil
                currentName = nil
                currentManufacturer = nil
            }
            guard let uuid = currentUUID,
                  let name = currentName,
                  let mfg = currentManufacturer else { return }
            // Skip Apple built-in / unsupported displays.
            if name == "(null)" { return }
            if mfg.lowercased() == "00-10-fa" { return }
            results.append(Display(uuid: uuid, productName: name, manufacturer: mfg))
        }

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("[") {
                // New display block — flush the previous one.
                flush()
                // "[2] LG ULTRAFINE (8C9D6B0B-D75A-...)"
                if let close = s.firstIndex(of: "]") {
                    let after = s.index(after: close)
                    let rest = s[after...].trimmingCharacters(in: .whitespaces)
                    if let openParen = rest.lastIndex(of: "("),
                       let closeParen = rest.lastIndex(of: ")"),
                       openParen < closeParen {
                        currentUUID = String(rest[rest.index(after: openParen)..<closeParen])
                        let name = rest[..<openParen].trimmingCharacters(in: .whitespaces)
                        currentName = name.isEmpty ? "(null)" : name
                    }
                }
            } else {
                let trimmed = s.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- Manufacturer:") {
                    currentManufacturer = trimmed
                        .replacingOccurrences(of: "- Manufacturer:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }
        flush()
        return results
    }

    /// Runs an m1ddc command targeting a specific display UUID.
    @discardableResult
    func run(_ uuid: String, _ args: [String]) async throws -> String {
        guard Self.isInstalled else { throw DDCError.binaryMissing }
        return try await Self.runRaw(["display", uuid] + args)
    }

    // DDC/CI is a serial bus. Concurrent m1ddc invocations collide and corrupt
    // each other's responses, so all subprocess calls are funneled through a
    // single serial queue regardless of caller concurrency.
    private static let serialQueue = DispatchQueue(label: "com.jigarthummar.LGMonitorControl.ddc")

    private static func runRaw(_ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            serialQueue.async {
                do {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: binaryPath)
                    proc.arguments = args
                    let out = Pipe()
                    let err = Pipe()
                    proc.standardOutput = out
                    proc.standardError = err
                    try proc.run()
                    proc.waitUntilExit()
                    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(),
                                        encoding: .utf8) ?? ""
                    if proc.terminationStatus != 0 {
                        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(),
                                            encoding: .utf8) ?? ""
                        cont.resume(throwing: DDCError.nonZeroExit(code: proc.terminationStatus, stderr: stderr))
                        return
                    }
                    cont.resume(returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    static func getInt(_ uuid: String, _ property: String) async throws -> Int {
        let raw = try await shared.run(uuid, ["get", property])
        guard let value = Int(raw) else {
            throw DDCError.nonZeroExit(code: -1, stderr: "unparseable: \(raw)")
        }
        return value
    }

    /// Returns `nil` when the display does not support reading the max for the
    /// given property (m1ddc errors out or returns a non-integer).
    static func maxInt(_ uuid: String, _ property: String) async -> Int? {
        do {
            let raw = try await shared.run(uuid, ["max", property])
            return Int(raw)
        } catch {
            return nil
        }
    }

    static func set(_ uuid: String, _ property: String, _ value: Int) async throws {
        try await shared.run(uuid, ["set", property, String(value)])
    }

    static func setMute(_ uuid: String, _ on: Bool) async throws {
        try await shared.run(uuid, ["set", "mute", on ? "on" : "off"])
    }
}
