import Foundation

// MARK: - Book source registry hook (engine side)
//
// The engine no longer owns a source list: the host app does (persisted, user
// editable). These hooks let engine features that *mutate* or *look up* the
// whole source list (health-check policy apply, cover-decode registry, deferred
// image resolution) work without depending on the app's store. The host wires a
// real implementation at launch; without one the hooks degrade to no-ops.

protocol BSBookSourceRegistry: AnyObject {
    /// All currently registered sources.
    var sources: [BSBookSource] { get }
    func source(withId id: UUID) -> BSBookSource?
    func source(withURL url: String) -> BSBookSource?
    func setEnabled(ids: Set<UUID>, enabled: Bool)
    @discardableResult func delete(ids: Set<UUID>) -> Int
    func setRespondTimes(_ times: [UUID: Int64])
}

/// Holder the engine reads. Replace `registry` from the app at startup.
final class BSRegistry: @unchecked Sendable {
    static let shared = BSRegistry()
    var registry: (any BSBookSourceRegistry)?

    var sources: [BSBookSource] { registry?.sources ?? [] }
    func source(withId id: UUID) -> BSBookSource? { registry?.source(withId: id) }
    func source(withURL url: String) -> BSBookSource? { registry?.source(withURL: url) }
    func setEnabled(ids: Set<UUID>, enabled: Bool) { registry?.setEnabled(ids: ids, enabled: enabled) }
    @discardableResult func delete(ids: Set<UUID>) -> Int { registry?.delete(ids: ids) ?? 0 }
    func setRespondTimes(_ times: [UUID: Int64]) { registry?.setRespondTimes(times) }
}
