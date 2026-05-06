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

actor DDC {
    static let shared = DDC()
    static let binaryPath = "/opt/homebrew/bin/m1ddc"

    private var cachedUUID: String?

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath)
    }

    private func resolveDisplay() async throws -> String {
        if let cached = cachedUUID { return cached }
        let listing = try await Self.runRaw(["display", "list"])
        // Lines look like: "[2] LG ULTRAFINE (8C9D6B0B-D75A-406E-0857-D6964E3302DB)"
        for line in listing.split(separator: "\n") {
            let s = String(line)
            let upper = s.uppercased()
            guard upper.contains("LG") else { continue }
            guard let open = s.lastIndex(of: "("),
                  let close = s.lastIndex(of: ")"),
                  open < close else { continue }
            let uuid = String(s[s.index(after: open)..<close])
            cachedUUID = uuid
            return uuid
        }
        throw DDCError.nonZeroExit(code: -1, stderr: "No LG display found in:\n\(listing)")
    }

    func invalidate() { cachedUUID = nil }

    @discardableResult
    func run(_ args: [String]) async throws -> String {
        guard Self.isInstalled else { throw DDCError.binaryMissing }
        let uuid = try await resolveDisplay()
        do {
            return try await Self.runRaw(["display", uuid] + args)
        } catch {
            // UUID may have changed (reboot, replug) — invalidate and retry once.
            cachedUUID = nil
            let fresh = try await resolveDisplay()
            return try await Self.runRaw(["display", fresh] + args)
        }
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

    static func getInt(_ property: String) async throws -> Int {
        let raw = try await shared.run(["get", property])
        guard let value = Int(raw) else {
            throw DDCError.nonZeroExit(code: -1, stderr: "unparseable: \(raw)")
        }
        return value
    }

    static func set(_ property: String, _ value: Int) async throws {
        try await shared.run(["set", property, String(value)])
    }

    static func setInputAlt(_ code: Int) async throws {
        try await shared.run(["set", "input-alt", String(code)])
    }

    static func setMute(_ on: Bool) async throws {
        try await shared.run(["set", "mute", on ? "on" : "off"])
    }
}
