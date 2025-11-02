import Foundation

/// リトライ戦略を制御する列挙型
///
/// ネットワークエラーなどの一時的な失敗時の再試行動作を制御します。
///
/// ## 使用例
/// ```swift
/// // リトライしない（デフォルト）
/// CachedRemoteImage(source: .url(imageURL), retryPolicy: .none)
///
/// // 3回まで固定間隔でリトライ
/// CachedRemoteImage(source: .url(imageURL), retryPolicy: .fixed(count: 3))
///
/// // 指数バックオフでリトライ（推奨：ネットワーク負荷を軽減）
/// CachedRemoteImage(source: .url(imageURL), retryPolicy: .exponentialBackoff(maxRetries: 3))
/// ```
public enum RetryPolicy: Equatable, Sendable {
    /// リトライしない
    case none

    /// 固定回数リトライ（即座に再試行）
    ///
    /// - Parameter count: リトライ回数（1以上）
    case fixed(count: Int)

    /// 指数バックオフでリトライ（推奨）
    ///
    /// 失敗するたびに待機時間を指数関数的に増加させることで、
    /// サーバーへの負荷を軽減し、一時的な問題からの回復を促進します。
    ///
    /// - Parameters:
    ///   - maxRetries: 最大リトライ回数（1以上）
    ///   - baseDelay: 基本待機時間（秒、デフォルト: 1.0）
    ///
    /// 実際の待機時間は `baseDelay * 2^(attemptNumber)` で計算されます。
    /// 例: baseDelay=1.0 の場合、1秒、2秒、4秒、8秒...
    case exponentialBackoff(maxRetries: Int, baseDelay: TimeInterval = 1.0)

    /// 最大リトライ回数
    internal var maxRetries: Int {
        switch self {
        case .none:
            return 0
        case .fixed(let count):
            return max(0, count)
        case .exponentialBackoff(let maxRetries, _):
            return max(0, maxRetries)
        }
    }

    /// 指定された試行回数に対する待機時間を計算
    ///
    /// - Parameter attemptNumber: 試行回数（0から始まる）
    /// - Returns: 待機時間（秒）
    internal func delay(for attemptNumber: Int) async -> TimeInterval {
        switch self {
        case .none:
            return 0
        case .fixed:
            return 0
        case .exponentialBackoff(_, let baseDelay):
            return baseDelay * pow(2.0, Double(attemptNumber))
        }
    }
}
