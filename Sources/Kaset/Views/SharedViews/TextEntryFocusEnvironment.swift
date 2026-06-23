import SwiftUI

// MARK: - Text Entry Focus Environment

/// Whether a text-entry field (e.g. the Search box) currently holds keyboard
/// focus.
///
/// Views that host a focusable `TextField` propagate their `@FocusState` into
/// this value so globally-installed media shortcuts (the hidden Space / ⌘-arrow
/// buttons in `PlayerBar`) can disable themselves while the user is typing.
/// Without this gate those key equivalents intercept the field editor — Space
/// fails to insert, and ⌘← / ⌘→ / ⌘↑ / ⌘↓ caret navigation is hijacked.
extension EnvironmentValues {
    @Entry var isTextEntryFocused: Bool = false
}
