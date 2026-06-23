// ToastView.swift
// Kaset
//
// A simple toast notification component for displaying transient messages.

import SwiftUI

// MARK: - ToastView

/// A toast notification that auto-dismisses after a configurable duration.
///
/// ## Usage
/// ```swift
/// @State private var showError = false
/// @State private var errorMessage: String?
///
/// .overlay(alignment: .top) {
///     if showError, let message = errorMessage {
///         ToastView(message: message, isError: true)
///             .task {
///                 // Auto-dismiss after 3 seconds
///                 try? await Task.sleep(for: .seconds(3))
///                 showError = false
///             }
///     }
/// }
/// ```
@available(macOS 26.0, *)
struct ToastView: View {
    // MARK: - Properties

    /// The message to display in the toast.
    let message: String

    /// Whether this is an error toast (uses red accent) or info toast.
    var isError: Bool = false

    /// Called when the toast should be dismissed.
    var onDismiss: (() -> Void)?

    // MARK: - Body

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 10) {
                // Icon
                Image(systemName: self.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(self.isError ? .red : .blue)

                // Message
                Text(self.message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                // Dismiss button
                if let dismiss = self.onDismiss {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Dismiss"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minWidth: 250, maxWidth: 400)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .glassEffectTransition(.materialize)
        .accessibilityIdentifier(AccessibilityID.Toast.container)
    }
}

// MARK: - AccountErrorToast

/// A toast that observes AccountService errors and auto-dismisses.
///
/// Add this to MainWindow as an overlay to show account switching errors.
@available(macOS 26.0, *)
struct AccountErrorToast: View {
    @Environment(AccountService.self) private var accountService

    @State private var isVisible = false
    @State private var dismissTask: Task<Void, Never>?

    /// Duration before auto-dismiss in seconds.
    private let autoDismissDelay: Duration = .seconds(4)

    var body: some View {
        Group {
            if self.isVisible, let error = accountService.lastError {
                ToastView(
                    message: self.errorMessage(for: error),
                    isError: true,
                    onDismiss: { self.dismiss() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: self.isVisible)
        .onChange(of: self.accountService.errorSequence) { _, _ in
            if self.accountService.lastError != nil {
                self.show()
            }
        }
    }

    // MARK: - Private Methods

    private func errorMessage(for error: Error) -> String {
        if let ytError = error as? YTMusicError {
            return ytError.localizedDescription
        }
        // Use appropriate message based on error context
        if self.accountService.lastErrorWasFetch {
            return String(localized: "Failed to load accounts. Please try again.")
        }
        return String(localized: "Failed to switch account. Please try again.")
    }

    private func show() {
        // Cancel any existing dismiss task
        self.dismissTask?.cancel()

        self.isVisible = true

        // Announce to VoiceOver so the transient toast is read regardless of focus.
        if let error = accountService.lastError {
            AccessibilityNotification.Announcement(self.errorMessage(for: error)).post()
        }

        // Schedule auto-dismiss
        self.dismissTask = Task {
            try? await Task.sleep(for: self.autoDismissDelay)
            if !Task.isCancelled {
                await MainActor.run {
                    self.dismiss()
                }
            }
        }
    }

    private func dismiss() {
        self.isVisible = false
        self.accountService.clearError()
        self.dismissTask?.cancel()
        self.dismissTask = nil
    }
}

// MARK: - ActionErrorPresenter

/// App-wide presenter for transient content-action error messages.
///
/// Fire-and-forget content actions (add to library, play album, like/dislike, …)
/// previously failed silently — they only logged. Routing their failures through
/// this shared presenter lets `ContentActionErrorToast` surface a transient toast
/// so the user gets feedback when an action fails (offline, expired session,
/// server error). A singleton is used so the static `SongActionsHelper` methods
/// can report failures without threading a dependency through every call site.
@available(macOS 26.0, *)
@MainActor
@Observable
final class ActionErrorPresenter {
    static let shared = ActionErrorPresenter()

    /// The most recent message to display. `nil` when nothing is pending.
    private(set) var lastMessage: String?

    /// Bumped on every `show(_:)` so observers re-trigger even for an identical message.
    private(set) var sequence: Int = 0

    private init() {}

    /// Presents an error message to the user.
    func show(_ message: String) {
        self.lastMessage = message
        self.sequence &+= 1
    }

    /// Presents a localized message derived from an error, mapping
    /// `YTMusicError.authExpired` to a sign-in prompt.
    func show(error: Error, fallback: String) {
        if let ytError = error as? YTMusicError {
            switch ytError {
            case .authExpired, .notAuthenticated:
                self.show(String(localized: "Your session expired. Please sign in again."))
            default:
                self.show(ytError.localizedDescription)
            }
        } else {
            self.show(fallback)
        }
    }

    func clear() {
        self.lastMessage = nil
    }
}

// MARK: - ContentActionErrorToast

/// A toast that observes `ActionErrorPresenter` and auto-dismisses.
///
/// Add this to MainWindow as an overlay to show content-action failures
/// (mirrors `AccountErrorToast`).
@available(macOS 26.0, *)
struct ContentActionErrorToast: View {
    @State private var presenter = ActionErrorPresenter.shared

    @State private var isVisible = false
    @State private var dismissTask: Task<Void, Never>?

    /// Duration before auto-dismiss in seconds.
    private let autoDismissDelay: Duration = .seconds(4)

    var body: some View {
        Group {
            if self.isVisible, let message = presenter.lastMessage {
                ToastView(
                    message: message,
                    isError: true,
                    onDismiss: { self.dismiss() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: self.isVisible)
        .onChange(of: self.presenter.sequence) { _, _ in
            if let message = presenter.lastMessage {
                self.show(message: message)
            }
        }
    }

    private func show(message: String) {
        self.dismissTask?.cancel()
        self.isVisible = true

        // Announce to VoiceOver so the transient toast is read regardless of focus.
        AccessibilityNotification.Announcement(message).post()

        self.dismissTask = Task {
            try? await Task.sleep(for: self.autoDismissDelay)
            if !Task.isCancelled {
                await MainActor.run {
                    self.dismiss()
                }
            }
        }
    }

    private func dismiss() {
        self.isVisible = false
        self.presenter.clear()
        self.dismissTask?.cancel()
        self.dismissTask = nil
    }
}

// MARK: - AccessibilityID.Toast

extension AccessibilityID {
    enum Toast {
        static let container = "toast.container"
    }
}

// MARK: - Preview

@available(macOS 26.0, *)
#Preview("Error Toast") {
    ToastView(message: "Failed to switch account. Please try again.", isError: true) {
        DiagnosticsLogger.ui.debug("Toast dismissed")
    }
    .padding()
}

@available(macOS 26.0, *)
#Preview("Info Toast") {
    ToastView(message: "Account switched successfully", isError: false)
        .padding()
}
