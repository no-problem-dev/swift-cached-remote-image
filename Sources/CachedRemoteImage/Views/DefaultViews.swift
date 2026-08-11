import SwiftUI

/// The view shown while an image loads, when you do not supply one.
///
/// A progress indicator filling whatever space it is given, so a list row keeps its height while
/// the fetch is in flight.
public struct DefaultLoadingView: View {
    public init() {}

    public var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The view shown when an image fails to load, when you do not supply one.
///
/// A warning symbol above the error's user-facing message. ``CachedRemoteImage`` builds it
/// without a retry action, so the button appears only when you construct one yourself.
public struct DefaultErrorView: View {
    public let error: ImageLoadError

    /// Called when the user taps retry. The button is hidden entirely when this is `nil`.
    public let onRetry: (() -> Void)?

    public init(error: ImageLoadError, onRetry: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text(error.localizedMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let onRetry = onRetry {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// The view shown before an image starts loading, when you do not supply one.
///
/// A translucent grey block, so the layout does not shift once the image arrives.
public struct DefaultPlaceholderView: View {
    public init() {}

    public var body: some View {
        Color.gray.opacity(0.2)
    }
}
