import Foundation

/// A hard time limit around an AI call. The caller gets an answer when the operation finishes,
/// when the deadline passes (`AIError.timedOut`), or when its task is cancelled
/// (`AIError.cancelled`), whichever comes first. The operation runs in its own task, so a
/// stuck await (or a non-cancellable call) can't keep the caller waiting: it's cancelled and
/// abandoned. URL requests stop on cancellation.
public enum AIDeadline {
    public static func run<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        let gate = DeadlineGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                gate.install(continuation)
                gate.start(
                    work: Task.detached {
                        do {
                            gate.finish(.success(try await operation()))
                        } catch {
                            gate.finish(.failure(error))
                        }
                    },
                    timer: Task.detached {
                        try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                        gate.finish(.failure(AIError.timedOut))
                    }
                )
            }
        } onCancel: {
            gate.finish(.failure(AIError.cancelled))
        }
    }
}

/// Resumes the caller exactly once, then cancels whatever is still running.
private final class DeadlineGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pending: Result<T, Error>?
    private var done = false
    private var work: Task<Void, Never>?
    private var timer: Task<Void, Never>?

    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let pending {
            // Cancelled before the continuation existed.
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func start(work: Task<Void, Never>, timer: Task<Void, Never>) {
        lock.lock()
        let finished = done
        if !finished {
            self.work = work
            self.timer = timer
        }
        lock.unlock()
        if finished {
            work.cancel()
            timer.cancel()
        }
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard !done else {
            lock.unlock()
            return
        }
        done = true
        let continuation = continuation
        self.continuation = nil
        if continuation == nil { pending = result }
        let work = work
        let timer = timer
        self.work = nil
        self.timer = nil
        lock.unlock()
        continuation?.resume(with: result)
        work?.cancel()
        timer?.cancel()
    }
}
