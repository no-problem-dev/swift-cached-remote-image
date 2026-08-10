import Foundation

/// Why an image could not be displayed.
///
/// The cause travels as text. Keeping the original error would cost `Sendable` and `Equatable`,
/// and stop the value crossing isolation boundaries — and the code that wants to branch on the
/// concrete type, to refresh a token or sign the user out, is the code that wrote the transport
/// and threw it. What the display side needs is something to show and a case to match on.
public enum ImageLoadError: Error, Equatable, Sendable {
    /// No library was found in the environment, so nothing could be fetched.
    ///
    /// Delivered to the error view like any other failure, instead of leaving an image that
    /// silently never appears.
    case libraryNotConfigured

    /// A string source could not be parsed as a URL. The string travels along so it can be shown.
    case invalidURL(String)

    /// The fetch failed, and the reason is whatever the transport or the download said it was.
    case transportFailed(reason: String)

    /// Bytes arrived but could not be decoded as an image.
    ///
    /// Never retried, since decoding the same bytes again gives the same answer, and the entry is
    /// dropped from the disk cache so it cannot keep answering later requests with this failure.
    case notAnImage(byteCount: Int)

    /// A short message that is safe to put in front of a user.
    ///
    /// Deliberately vague about the cause, and written in Japanese with no localization table
    /// behind it. Use `errorDescription` when you want the detail.
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
    /// A developer-facing description that keeps the detail the user-facing message drops.
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

/// The stage a single image load has reached, as the view sees it.
///
/// A load moves through the sequence once and never goes back:
/// ```
/// idle → loading → success or failure
/// ```
///
/// - Note: Not `Sendable`. It carries a decoded ``PlatformImage``, which is not sendable on
///   macOS, so this is meant to be read on the main actor.
public enum LoadingState {
    /// Nothing has been requested yet, and the placeholder is showing.
    case idle

    /// A fetch is in flight, including any retries.
    ///
    /// - Parameter progress: How much has arrived, from 0 to 1, or `nil` when the total length is
    ///   not known.
    case loading(progress: Double?)

    /// The image is decoded and ready to display.
    ///
    /// - Parameter image: The decoded image.
    case success(PlatformImage)

    /// The load ended in failure and the error view is showing.
    ///
    /// - Parameter error: What went wrong.
    case failure(ImageLoadError)

    /// Whether the load has settled, whether it succeeded or failed.
    public var isCompleted: Bool {
        switch self {
        case .success, .failure:
            return true
        case .idle, .loading:
            return false
        }
    }

    public var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    public var isFailure: Bool {
        if case .failure = self {
            return true
        }
        return false
    }

    public var image: PlatformImage? {
        if case .success(let image) = self {
            return image
        }
        return nil
    }

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
            // Two successes compare equal by state alone, not by which image each one holds.
            return true
        case (.failure(let lhsError), .failure(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}
