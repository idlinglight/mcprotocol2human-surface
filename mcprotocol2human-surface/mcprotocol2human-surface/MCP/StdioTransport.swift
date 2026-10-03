import Foundation

/// Starts a server as a child process and exchanges newline-delimited JSON over its stdin and stdout.
/// Lines on stderr go to the traffic record as the server's log.
///
/// Closing follows the specification: close stdin, wait, then SIGTERM, then SIGKILL. Processes the server
/// started itself are not signalled; a well-behaved server takes them down when its stdin closes.
nonisolated final class StdioTransport: MCPTransport, @unchecked Sendable {
    let command: String
    let arguments: [String]
    let environment: [String: String]
    let traffic: TrafficLog
    let events: AsyncStream<TransportEvent>
    var repliesArriveWithSend: Bool { false }

    private let continuation: AsyncStream<TransportEvent>.Continuation
    // Guarded by `lock`.
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var stdoutLines = LineSplitter()
    private var stderrLines = LineSplitter()
    private var stdoutEnded = false
    private var exitDescription: String?
    private var finished = false

    init(command: String, arguments: [String], environment: [String: String], traffic: TrafficLog) {
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.traffic = traffic
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() async throws {
        guard let url = ExecutableLocator.resolve(command) else {
            throw TransportError.executableNotFound(command)
        }
        // Writing to a server that has exited must fail with EPIPE, not end this app.
        signal(SIGPIPE, SIG_IGN)

        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        process.environment = ExecutableLocator.childEnvironment(adding: environment)
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            self?.receiveStdout(data)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            self?.receiveStderr(data)
        }
        process.terminationHandler = { [weak self] process in
            self?.exited(status: process.terminationStatus, reason: process.terminationReason)
        }

        traffic.record(.note, "Starting \(([url.path] + arguments).joined(separator: " "))")
        do {
            try process.run()
        } catch {
            throw TransportError.launchFailed(command, reason: error.localizedDescription)
        }
        lock.withLock {
            self.process = process
            self.input = stdin.fileHandleForWriting
        }
    }

    func send(_ message: OutgoingMessage) async throws -> [JSONValue] {
        guard let input = lock.withLock({ self.input }) else {
            throw TransportError.writeFailed("the server is not running")
        }
        do {
            try input.write(contentsOf: message.payload.compactData + Data([0x0A]))
        } catch {
            throw TransportError.writeFailed(error.localizedDescription)
        }
        return []
    }

    func setProtocolHeaders(version: String?, namesMethod: Bool) async {}

    func close() async {
        let (process, input) = lock.withLock { (self.process, self.input) }
        lock.withLock { self.input = nil }
        try? input?.close()
        guard let process else {
            finish(reason: "never started")
            return
        }
        if await waitForExit(process, seconds: 2) { return }
        traffic.record(.note, "The server did not exit after its input closed; sending SIGTERM.")
        process.terminate()
        if await waitForExit(process, seconds: 2) { return }
        traffic.record(.note, "The server ignored SIGTERM; sending SIGKILL.")
        kill(process.processIdentifier, SIGKILL)
        _ = await waitForExit(process, seconds: 2)
    }

    private func waitForExit(_ process: Process, seconds: Double) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while process.isRunning {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    // MARK: Output

    private func receiveStdout(_ data: Data) {
        let lines: [[UInt8]] = lock.withLock {
            if data.isEmpty {
                stdoutEnded = true
                return stdoutLines.finish().map { [$0] } ?? []
            }
            return stdoutLines.append(data)
        }
        for bytes in lines {
            let text = String(decoding: bytes, as: UTF8.self)
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            traffic.record(.received, text)
            do {
                continuation.yield(.message(try JSONValue.parse(Data(bytes))))
            } catch {
                traffic.record(.note, "That line on stdout is not JSON (\(error.localizedDescription)). Only MCP messages belong on stdout.")
            }
        }
        if data.isEmpty { finishIfDone() }
    }

    private func receiveStderr(_ data: Data) {
        let lines: [[UInt8]] = lock.withLock {
            if data.isEmpty { return stderrLines.finish().map { [$0] } ?? [] }
            return stderrLines.append(data)
        }
        for bytes in lines {
            traffic.record(.stderr, String(decoding: bytes, as: UTF8.self))
        }
    }

    private func exited(status: Int32, reason: Process.TerminationReason) {
        let description = reason == .uncaughtSignal ? "ended by signal \(status)" : "exited with status \(status)"
        lock.withLock { exitDescription = description }
        traffic.record(.note, "The server \(description).")
        // Give stdout a moment to drain; a process the server started may also hold it open.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.finish(reason: "The server \(description).")
        }
        finishIfDone()
    }

    private func finishIfDone() {
        let (ended, exit) = lock.withLock { (stdoutEnded, exitDescription) }
        if ended, let exit { finish(reason: "The server \(exit).") }
    }

    private func finish(reason: String) {
        let first = lock.withLock {
            defer { finished = true }
            return !finished
        }
        guard first else { return }
        continuation.yield(.closed(reason))
        continuation.finish()
    }
}
