import Foundation

/// ディスク上の画像バイト列。**ネットワークには行かない。**
///
/// WidgetKit のタイムライン生成は非同期のネットワーク取得ができない。
/// 「ディスクにあるものだけを、同期で、すぐ返す」入口が要る。
/// この型はネットワークに出る手段を一切持たないので、
/// ウィジェットに渡しても取得のために固まることが起こりえない。
///
/// アプリ本体は ``ImageLibrary`` を使う（この型はその内側にも居る）。
/// ウィジェットはこの型を直接作り、アプリ本体と**同じ ``ImageCacheLocation``** を渡す。
///
/// ## ウィジェットでの使い方
/// ```swift
/// let cache = try ImageDiskCache(location: .appGroup("group.com.example.app"))
/// if let data = cache.imageData(for: item.imageId), let image = UIImage(data: data) {
///     Image(uiImage: image)
/// } else {
///     Text(item.emoji)   // 無ければ落とす先を用意しておく
/// }
/// ```
///
/// ## 保存されるのは受け取ったバイト列そのもの
/// 3.x は `UIImage` に復号してから JPEG q0.8 で再エンコードして書いていた。
/// 取得済みのバイト列を捨てて劣化した別のバイト列を作る動きで、PNG の透過も失われていた。
/// 4.0 では受け取った Data をそのまま書く。だから ``imageData(for:)`` が返すのは
/// サーバーが返した実物であり、ウィジェット側で余計な変換が要らない。
public struct ImageDiskCache: Sendable {
    private let directory: URL
    private let sizeLimit: Int64

    /// - Parameters:
    ///   - location: 保存場所。ウィジェットと共有するなら ``ImageCacheLocation/appGroup(_:subdirectory:)``
    ///   - sizeLimit: ディスク使用量の上限（バイト）。超えたぶんは古い順に消す
    /// - Throws: 場所を解決・作成できなかったとき。App Group の entitlement 忘れなど
    public init(location: ImageCacheLocation = .caches, sizeLimit: Int64 = 100 * 1024 * 1024) throws {
        self.directory = try location.resolvedDirectory()
        self.sizeLimit = sizeLimit
    }

    /// キャッシュ済みの画像バイト列を同期で返す。無ければ `nil`。
    ///
    /// **ネットワークには行かない。** `nil` は「まだ端末に無い」だけを意味する。
    ///
    /// - Parameter id: 画像 ID
    public func imageData(for id: String) -> Data? {
        data(for: .id(id))
    }

    /// 画像 ID のバイト列が端末にあるか。読み込まずに存在だけ見る
    public func contains(_ id: String) -> Bool {
        contains(.id(id))
    }

    /// ディスクキャッシュの合計サイズ（バイト）
    public func totalBytes() -> Int64 {
        entries().reduce(Int64(0)) { $0 + $1.size }
    }

    /// すべて削除する
    public func removeAll() {
        guard let contents = try? FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - 内部（URL 経路のキーも扱えるようにするため、公開 API とは別口にしてある）

    func data(for key: ImageCacheKey) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    func contains(_ key: ImageCacheKey) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: key).path)
    }

    /// バイト列を保存し、上限を超えていれば古い順に消す。
    ///
    /// 書き込みはネットワーク往復のあとにしか起きないので、
    /// そのたびにディレクトリを走査してもコストは埋もれる。
    /// 走査を省くために書き込み量を別に持つと、プロセスをまたいだ時点で嘘になる
    /// （アプリとウィジェットが同じディレクトリを共有する）。
    func store(_ data: Data, for key: ImageCacheKey) {
        try? data.write(to: fileURL(for: key), options: .atomic)
        trimToSizeLimit()
    }

    func remove(for key: ImageCacheKey) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    // MARK: - Private

    private func fileURL(for key: ImageCacheKey) -> URL {
        directory.appendingPathComponent(key.fileName)
    }

    private struct Entry {
        let url: URL
        let size: Int64
        let modifiedAt: Date
    }

    private func entries() -> [Entry] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else {
            return []
        }
        return contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { return nil }
            return Entry(url: url, size: Int64(size), modifiedAt: values.contentModificationDate ?? .distantPast)
        }
    }

    /// 上限を超えたぶんを古い順に消す。
    ///
    /// App Group に置いた場合、OS は容量不足でも消してくれない。
    /// 上限を持たないと、画像を見るほど端末の空きが減り続けて戻らない。
    private func trimToSizeLimit() {
        let all = entries()
        var total = all.reduce(Int64(0)) { $0 + $1.size }
        guard total > sizeLimit else { return }

        for entry in all.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            guard total > sizeLimit else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
