import Foundation

/// Lazy-loading lifecycle state of an ad unit.
///
/// notLoaded -> fetched (within the fetch zone) -> displayed (within the
/// display zone) -> unloaded (outside the unload zone for the stability
/// delay, only when unloading is enabled) -> notLoaded on re-entry.
public enum AdLoadState: String, CaseIterable, Equatable, Identifiable {
    public var id: String { self.rawValue }
    case notLoaded
    case fetched
    case displayed
    case unloaded
}
