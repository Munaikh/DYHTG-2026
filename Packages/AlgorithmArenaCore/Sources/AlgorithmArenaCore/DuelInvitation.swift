/// The QR invitation format for Plot Twist Duel. This is a payload decoder, not
/// a URL opener: scanning an invitation never navigates to an external address.
public enum DuelInvitation {
  private static let prefix = "algorithm-arena://duel/join?code="

  /// Duel room codes are six hexadecimal characters, matching the server schema.
  public static func payload(for roomCode: String) -> String? {
    guard let code = normalizedCode(roomCode) else { return nil }
    return prefix + code
  }

  /// Accept our exact versionless envelope or a legacy QR containing only a code.
  /// Exact grammar intentionally excludes credentials, fragments, extra/duplicate
  /// query keys, percent-encoded alternatives, and codes buried in unrelated text.
  public static func roomCode(from payload: String) -> String? {
    // Bound scanning work even when a QR supplies a very large payload.
    guard payload.utf8.prefix(129).count <= 128 else { return nil }
    if let code = normalizedCode(payload) { return code }
    guard payload.hasPrefix(prefix) else { return nil }
    return normalizedCode(String(payload.dropFirst(prefix.count)))
  }

  private static func normalizedCode(_ code: String) -> String? {
    let bytes = Array(code.utf8.prefix(7))
    guard bytes.count == 6 else { return nil }
    var normalized: [UInt8] = []
    for byte in bytes {
      switch byte {
      case 48...57, 65...70: normalized.append(byte)
      case 97...102: normalized.append(byte - 32)
      default: return nil
      }
    }
    return String(decoding: normalized, as: UTF8.self)
  }
}
