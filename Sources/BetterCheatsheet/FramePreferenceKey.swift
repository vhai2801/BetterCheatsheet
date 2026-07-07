import SwiftUI

/// Marker types purely so distinct call sites get their own preference
/// "channel" - SwiftUI's preference propagation is scoped per conforming
/// *type*, not per usage site, so e.g. a view's row frames and its grip-
/// handle frames (both `[UUID: CGRect]`, both keyed by the same row IDs)
/// would silently merge into one dictionary and clobber each other if they
/// shared a single concrete PreferenceKey type.
protocol FrameTag {}
enum RowFrameTag: FrameTag {}
enum GripFrameTag: FrameTag {}
enum TabFrameTag: FrameTag {}

/// Generic `[UUID: CGRect]`-merging PreferenceKey, replacing three
/// structurally-identical bespoke types (row/grip frames in
/// ShortcutTableView, tab frames in TabBarView) that only differed in name.
struct UUIDFramePreferenceKey<Tag: FrameTag>: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
