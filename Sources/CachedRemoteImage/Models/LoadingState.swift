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
    /// Deliberately vague about the cause, and written in English with no localization table
    /// behind it. Use `errorDescription` when you want the detail.
    public var localizedMessage: String {
        switch self {
        case .libraryNotConfigured:
            return "Image loading isn't set up"
        case .invalidURL:
            return "That image address isn't valid"
        case .transportFailed:
            return "Couldn't load the image"
        case .notAnImage:
            return "Couldn't display the image"
        }
    }
}

extension ImageLoadError {
    /// Records an error from a transport or a download as a transport failure, keeping what it
    /// actually said.
    ///
    /// Not `localizedDescription`. Foundation answers that, for any error that did not opt in to
    /// `LocalizedError`, with a fixed sentence naming the type and a case number: a
    /// `FetchFailure(reason: "token expired")` arrives as "The operation couldn't be completed.
    /// (App.FetchFailure error 1.)", and `.unauthorized` and `.notFound` on one enum differ only
    /// by that number. The sentence is translated into the device's language too, so the one
    /// piece of text a developer has to work from changes with whoever is holding the phone.
    static func transportFailed(wrapping error: any Error) -> ImageLoadError {
        .transportFailed(reason: describing(error))
    }

    private static func describing(_ error: any Error) -> String {
        // What the author of the error wrote, when they wrote one.
        if let described = (error as? any LocalizedError)?.errorDescription {
            return described
        }
        // Errors bridged from `NSError` — URLSession's among them — carry a real sentence here.
        if let described = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String {
            return described
        }
        // Everything else: the Swift value, which still holds its case name and payload.
        return String(describing: error)
    }
}

extension ImageLoadError: LocalizedError {
    /// A developer-facing description that keeps the detail the user-facing message drops.
    public var errorDescription: String? {
        switch self {
        case .libraryNotConfigured:
            return "No ImageLibrary in the environment. Call .imageLibrary(_:) on the root view"
        case .invalidURL(let string):
            return "Could not read as a URL: \(string)"
        case .transportFailed(let reason):
            return "The fetch failed: \(reason)"
        case .notAnImage(let byteCount):
            return "The \(byteCount) bytes received could not be decoded as an image"
        }
    }
}

/// The stage a single image load has reached, as the view sees it.
///
/// A load settles once:
/// ```
/// idle → loading → success or failure
/// ```
/// with one way back: a cancelled load returns to `idle`, because nothing about it failed and the
/// same view may come round again.
///
/// - Note: Not `Sendable`. It carries a decoded ``PlatformImage``, which is not sendable on
///   macOS, so this is meant to be read on the main actor.
public enum LoadingState {
    /// No load is outstanding, and the placeholder is showing.
    ///
    /// Both the state before anything is requested and the state a cancelled load returns to.
    case idle

    /// A fetch is in flight, including any retries.
    ///
    /// How far along it is is not reported. ``ImageTransport/fetch(id:)`` hands back the bytes in
    /// one piece, so there is no point at which a fraction could be known, and a `progress` that
    /// was always `nil` only invited determinate progress bars that never moved.
    case loading

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
        case (.loading, .loading):
            return true
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
