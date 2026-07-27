import SwiftUI

/// デフォルトのローディングビュー
///
/// シンプルなプログレスインジケーターを表示する。
public struct DefaultLoadingView: View {
    public init() {}

    public var body: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// デフォルトのエラービュー
///
/// エラーメッセージとリトライボタンを表示する。`onRetry` を渡すと再試行ボタンが現れる。
public struct DefaultErrorView: View {
    /// 表示するエラー
    public let error: ImageLoadError
    /// 再試行時に呼ばれるクロージャ。`nil` の場合は再試行ボタンを非表示にする。
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
/// 読み込み開始前に表示するシンプルなビュー。半透明グレーで領域を確保する。
public struct DefaultPlaceholderView: View {
    public init() {}

    public var body: some View {
        Color.gray.opacity(0.2)
    }
}
