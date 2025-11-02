import SwiftUI

/// デフォルトのローディングビュー
///
/// シンプルなプログレスインジケーターを表示します。
public struct DefaultLoadingView: View {
    public init() {}

    public var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// デフォルトのエラービュー
///
/// エラーメッセージとリトライボタンを表示します。
public struct DefaultErrorView: View {
    let error: ImageLoadError
    let onRetry: (() -> Void)?

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
                    Label("再試行", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// デフォルトのプレースホルダービュー
///
/// 読み込み開始前に表示するシンプルなビューです。
public struct DefaultPlaceholderView: View {
    public init() {}

    public var body: some View {
        Color.gray.opacity(0.2)
    }
}
