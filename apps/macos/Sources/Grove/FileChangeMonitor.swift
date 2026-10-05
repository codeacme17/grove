import CoreServices
import Foundation

// FSEvents delivers on a serial queue; teardown may also run from task cancellation.
final class FileChangeMonitor: @unchecked Sendable {
    let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var fallback: Task<Void, Never>?
    private var stopped = false

    private final class Sink {
        let continuation: AsyncStream<Void>.Continuation
        init(_ continuation: AsyncStream<Void>.Continuation) { self.continuation = continuation }
    }

    init(paths: [String]) {
        (events, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        let sink = Sink(continuation)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(sink).toOpaque(), retain: { info in
            if let info { _ = Unmanaged<Sink>.fromOpaque(info).retain() }
            return info
        }, release: { info in
            if let info { Unmanaged<Sink>.fromOpaque(info).release() }
        }, copyDescription: nil)
        let roots = Array(Set(paths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }))
        let created = withExtendedLifetime(sink) {
            FSEventStreamCreate(nil, { _, info, _, _, _, _ in
                guard let info else { return }
                Unmanaged<Sink>.fromOpaque(info).takeUnretainedValue().continuation.yield(())
            }, &context, roots as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
               FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagFileEvents))
        }
        if let created {
            FSEventStreamSetDispatchQueue(created, DispatchQueue(label: "grove.file-changes", qos: .utility))
            if FSEventStreamStart(created) {
                stream = created
            } else {
                FSEventStreamInvalidate(created)
                FSEventStreamRelease(created)
            }
        }
        if stream == nil {
            // Keep automatic updates available if the event service cannot be started.
            fallback = Task { [continuation] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { return }
                    continuation.yield(())
                }
            }
        }
        continuation.onTermination = { [weak self] _ in self?.stop() }
        continuation.yield(())
    }

    func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let stream = self.stream
        let fallback = self.fallback
        self.stream = nil
        self.fallback = nil
        lock.unlock()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        fallback?.cancel()
        continuation.finish()
    }

    deinit { stop() }
}
