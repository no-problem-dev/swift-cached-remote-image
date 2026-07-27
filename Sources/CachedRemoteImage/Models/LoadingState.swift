import Foundation

/// 画像を表示できなかった原因。
///
/// 原因は説明文で運ぶ。元のエラー型をそのまま持たせると `Sendable`・`Equatable` を諦めることになり、
/// 隔離をまたいで運べなくなる。そして原因の型で分岐したい側 — 認証切れを検知して
/// サインインへ送る、といった処理 — は ``ImageTransport`` を書いた側なので、
/// 自分が投げたエラーをそこで捕まえられる。表示のこちら側に要るのは、出せる文言と種別だけ。
public enum ImageLoadError: Error, Equatable, Sendable {
    /// ``ImageLibrary`` が環境に注入されていない。
    ///
    /// 3.x はここで `print` して素通りしていたので、画像が出ない理由が
    /// コンソールにしか出なかった。エラーとして扱えば、エラービューにそのまま出る
    case libraryNotConfigured

    /// URL 文字列を URL にできなかった
    case invalidURL(String)

    /// 取得に失敗した（``ImageTransport`` またはダウンロードが投げた）
    case transportFailed(reason: String)

    /// バイト列は取れたが、画像として復号できなかった。
    ///
    /// 同じバイト列を再試行しても結果は変わらないので、再試行の対象にしない
    case notAnImage(byteCount: Int)

    /// ユーザーに表示するエラーメッセージ
    public var localizedMessage: String {
        switch self {
        case .libraryNotConfigured:
            return "画像の読み込み設定がされていません"
        case .invalidURL:
            return "無効な画像URLです"
        case .transportFailed:
            return "画像の取得に失敗しました"
        case .notAnImage:
            return "画像を表示できませんでした"
        }
    }
}

extension ImageLoadError: LocalizedError {
    /// 開発者向けの説明。``localizedMessage`` と違い、原因の詳細を落とさない
    public var errorDescription: String? {
        switch self {
        case .libraryNotConfigured:
            return "ImageLibrary が未注入（ルートビューで .imageLibrary(_:) を呼ぶ）"
        case .invalidURL(let string):
            return "URL として解釈できない文字列: \(string)"
        case .transportFailed(let reason):
            return "画像の取得に失敗: \(reason)"
        case .notAnImage(let byteCount):
            return "受け取った \(byteCount) バイトが画像として復号できない"
        }
    }
}

/// 画像の読み込み状態を表す列挙型
///
/// UI の状態管理を明確にし、適切な表示を可能にする。
///
/// ## 状態遷移
/// ```
/// idle → loading → success or failure
/// ```
///
/// - Note: MainActorで使用されることを想定しているため、Sendableに準拠していません。
public enum LoadingState {
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
