import Testing
@testable import AlgorithmArenaCore

struct DuelInvitationTests {
  @Test(arguments: ["ABC123", "000000", "FFFFFF", "abcdef", "a1B2c3"])
  func generatedInvitationsRoundTrip(_ code: String) throws {
    let payload = try #require(DuelInvitation.payload(for: code))
    #expect(payload == "algorithm-arena://duel/join?code=\(code.uppercased())")
    #expect(DuelInvitation.roomCode(from: payload) == code.uppercased())
    #expect(DuelInvitation.roomCode(from: code) == code.uppercased())
  }

  @Test func lowercaseCodeInEnvelopeIsNormalized() {
    #expect(DuelInvitation.roomCode(from: "algorithm-arena://duel/join?code=a1b2c3") == "A1B2C3")
  }

  @Test(arguments: ["", "ABC12", "ABC1234", "GHI123", "１２３４５６", "АBC123",
                    "ABC12é", "ABC12\n", " ABC123", "ABC123 ", "AB-C12", "ABC\u{0}12"])
  func invalidCodesCannotBeEncodedOrScanned(_ code: String) {
    #expect(DuelInvitation.payload(for: code) == nil)
    #expect(DuelInvitation.roomCode(from: code) == nil)
    #expect(DuelInvitation.roomCode(from: "algorithm-arena://duel/join?code=" + code) == nil)
  }

  @Test(arguments: [
    "https://example.com/?code=ABC123",
    "https://algorithm-arena/duel/join?code=ABC123",
    "algorithm-arena://other/join?code=ABC123",
    "algorithm-arena://duel/leave?code=ABC123",
    "algorithm-arena://duel/join/?code=ABC123",
    "algorithm-arena://duel/join?code=ABC123&code=DEF456",
    "algorithm-arena://duel/join?code=ABC123&code=ABC123",
    "algorithm-arena://duel/join?code=ABC123&extra=1",
    "algorithm-arena://duel/join?extra=1&code=ABC123",
    "algorithm-arena://duel/join?code=ABC123&",
    "algorithm-arena://duel/join?code=ABC123#fragment",
    "algorithm-arena://duel/join?code=ABC123#",
    "algorithm-arena://duel/join?code=%41BC123",
    "algorithm-arena://duel/join?%63ode=ABC123",
    "algorithm-arena://duel/join?code=ABC123%",
    "algorithm-arena://duel/join?code=",
    "algorithm-arena://duel/join?code",
    "algorithm-arena://duel/join?Code=ABC123",
    "algorithm-arena://user@duel/join?code=ABC123",
    "algorithm-arena://duel:123/join?code=ABC123",
    "Join my room ABC123",
    " algorithm-arena://duel/join?code=ABC123",
    "algorithm-arena://duel/join?code=ABC123\n",
  ])
  func unrelatedOrMalformedPayloadIsRejected(_ payload: String) {
    #expect(DuelInvitation.roomCode(from: payload) == nil)
  }

  @Test func oversizedPayloadIsRejected() {
    let payload = "algorithm-arena://duel/join?code=ABC123" + String(repeating: "A", count: 100_000)
    #expect(DuelInvitation.roomCode(from: payload) == nil)
    #expect(DuelInvitation.payload(for: String(repeating: "A", count: 100_000)) == nil)
  }
}
