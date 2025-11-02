import Foundation

/// 画像読み込みエラーの種類
///
/// エラーの原因を特定し、適切なエラーハンドリングを可能にします。
public enum ImageLoadError: Error, Equatable, Sendable {
    /// メタデータの取得に失敗
    case metadataFetchFailed(String)

    /// 無効なURL
    case invalidURL(String)

    /// 画像のダウンロードに失敗
    case downloadFailed

    /// ネットワークエラー
    case networkError(String)

    /// その他のエラー
    case unknown(String)

    /// ユーザーに表示するエラーメッセージ
    public var localizedMessage: String {
        switch self {
        case .metadataFetchFailed:
            return "画像情報の取得に失敗しました"
        case .invalidURL:
            return "無効な画像URLです"
        case .downloadFailed:
            return "画像のダウンロードに失敗しました"
        case .networkError:
            return "ネットワークエラーが発生しました"
        case .unknown:
            return "画像の読み込みに失敗しました"
        }
    }
}

/// 画像の読み込み状態を表す列挙型
///
/// UIの状態管理を明確にし、適切な表示を可能にします。
///
/// ## 状態遷移
/// ```
/// idle → loading → success or failure
/// ```
public enum LoadingState: Sendable {
    /// 読み込み開始前（初期状態）
    case idle

    /// 読み込み中
    ///
    /// - Parameter progress: 進捗状況（0.0〜1.0、nilの場合は不定）
    case loading(progress: Double?)

    /// 読み込み成功
    ///
    /// - Parameter image: 読み込まれた画像
    case success(PlatformImage)

    /// 読み込み失敗
    ///
    /// - Parameter error: エラーの詳細
    case failure(ImageLoadError)

    /// 読み込みが完了しているかどうか
    public var isCompleted: Bool {
        switch self {
        case .success, .failure:
            return true
        case .idle, .loading:
            return false
        }
    }

    /// 読み込みに成功したかどうか
    public var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    /// 読み込みに失敗したかどうか
    public var isFailure: Bool {
        if case .failure = self {
            return true
        }
        return false
    }

    /// 成功時の画像を取得
    public var image: PlatformImage? {
        if case .success(let image) = self {
            return image
        }
        return nil
    }

    /// 失敗時のエラーを取得
    public var error: ImageLoadError? {
        if case .failure(let error) = self {
            return error
        }
        return nil
    }
}

// MARK: - Equatable

extension LoadingState: Equatable {
    public static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.loading(let lhsProgress), .loading(let rhsProgress)):
            return lhsProgress == rhsProgress
        case (.success, .success):
            // 画像の同一性は参照ではなく状態のみで判定
            return true
        case (.failure(let lhsError), .failure(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}
