import Foundation

/// A process-wide budget for artwork work (network AND decoding).
/// Waiters are cancellable, and an acquired slot is released by the caller.
public actor ArtworkGate {
    private let limit: Int
    private var active = 0
    private var waiters: [(UUID, CheckedContinuation<Bool, Never>)] = []
    public init(limit: Int = 4) { self.limit = max(1,limit) }
    public func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if active < limit { active += 1; return true }
        let id = UUID()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning:false) }
                else { waiters.append((id,continuation)) }
            }
        }, onCancel: { Task { await self.cancel(id) } })
    }
    private func cancel(_ id: UUID) {
        guard let i=waiters.firstIndex(where:{$0.0==id}) else { return }
        waiters.remove(at:i).1.resume(returning:false)
    }
    public func release() {
        guard active > 0 else {return}
        if !waiters.isEmpty { waiters.removeFirst().1.resume(returning:true) }
        else {active -= 1}
    }
    func counts() -> (active: Int, waiting: Int) { (active,waiters.count) }
}
