import Foundation

public struct GitRunner: Sendable {
    private let executable: URL
    private let timeout: TimeInterval

    public init(executable: URL? = nil, timeout: TimeInterval = 15) {
        self.executable = executable ?? ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            ?? URL(fileURLWithPath: "/usr/bin/git")
        self.timeout = timeout
    }

    public func run(_ arguments: [String]) async throws -> Data {
        let execution = Execution()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try execution.run(executable: executable, arguments: arguments, timeout: timeout)
                    })
                }
            }
        } onCancel: { execution.stop() }
    }
}

// Process state is protected by the lock; blocking I/O runs on a Dispatch worker.
private final class Execution: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private var timedOut = false

    func stop(timeout: Bool = false) {
        lock.lock()
        stopped = true
        timedOut = timedOut || timeout
        if let process, process.isRunning {
            process.terminate()
            // Escalate only while the same Process still reports itself running.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
                lock.lock()
                defer { lock.unlock() }
                if let process = self.process, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
            }
        }
        lock.unlock()
    }

    func run(executable: URL, arguments: [String], timeout: TimeInterval) throws -> Data {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let outputURL = folder.appendingPathComponent("stdout")
        let errorURL = folder.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        let errors = try FileHandle(forWritingTo: errorURL)
        defer { try? output.close(); try? errors.close() }

        let command = Process()
        command.executableURL = executable
        command.arguments = arguments
        command.standardInput = FileHandle.nullDevice
        command.standardOutput = output
        command.standardError = errors
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["LC_ALL"] = "C"
        command.environment = environment

        lock.lock()
        if stopped { lock.unlock(); throw CancellationError() }
        process = command
        do { try command.run() } catch {
            process = nil
            lock.unlock()
            throw GroveError.message("Could not launch Git. Install Git or the Xcode Command Line Tools.\n\(error.localizedDescription)")
        }
        lock.unlock()

        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [self] in stop(timeout: true) }
        timer.resume()
        command.waitUntilExit()
        timer.cancel()

        lock.lock()
        process = nil
        let didTimeOut = timedOut
        let didStop = stopped
        lock.unlock()
        if didTimeOut { throw GroveError.message("Git took too long to respond. Check that the repository drive is available, then retry.") }
        if didStop { throw CancellationError() }
        guard command.terminationStatus == 0 else {
            let detail = String(decoding: try Data(contentsOf: errorURL), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GroveError.message(detail.isEmpty ? "Git exited with status \(command.terminationStatus)." : detail)
        }
        return try Data(contentsOf: outputURL)
    }
}
