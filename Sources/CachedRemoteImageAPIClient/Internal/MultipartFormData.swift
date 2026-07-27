import Foundation

/// `multipart/form-data` のリクエストボディを組み立てる。
///
/// 3.x はバイト列を Base64 にして JSON に入れていた。転送量が 33% 増え、
/// エンコード後の全量がメモリに載り、サーバー側も base64 を解く実装を強いられていた。
/// 画像を送る標準の形は multipart なので、そちらに合わせる。
struct MultipartFormData {
    /// 境界文字列。ヘッダーの `boundary=` とボディの区切りが一致している必要があるので、
    /// 組み立てる側が一度だけ決めて両方に配る
    let boundary: String

    init(boundary: String = "CachedRemoteImage-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// `Content-Type` ヘッダーの値
    var contentTypeHeaderValue: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// ファイルパート 1 つだけのボディを組み立てる
    ///
    /// - Parameters:
    ///   - fieldName: フォームのフィールド名（サーバーが読む名前）
    ///   - fileName: ファイル名。多くのサーバーはこれの有無でファイルとして扱うかを決める
    ///   - contentType: MIME タイプ
    ///   - data: 中身
    func body(fieldName: String, fileName: String, contentType: String, data: Data) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// MIME タイプからファイル名を作る。
    ///
    /// 拡張子だけで中身を判定するサーバーがあるので、型と食い違わない名前を付ける
    static func fileName(for contentType: String) -> String {
        let subtype = contentType.split(separator: "/").last.map(String.init) ?? "bin"
        switch subtype {
        case "jpeg": return "image.jpg"
        case "svg+xml": return "image.svg"
        default: return "image.\(subtype)"
        }
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
