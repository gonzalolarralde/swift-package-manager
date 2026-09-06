public func embeddedResourceText() throws -> String {
    precondition(PackageResources.empty_bin.isEmpty)
    precondition(PackageResources.empty_bin.byteCount == 0)
    let bytes: RawSpan = PackageResources.best_txt
    if #available(macOS 26, *) {
        return String(copying: try UTF8Span(validating: Span<UInt8>(_bytes: bytes)))
    }
    return bytes.withUnsafeBytes {
        String(decoding: $0, as: UTF8.self)
    }
}
