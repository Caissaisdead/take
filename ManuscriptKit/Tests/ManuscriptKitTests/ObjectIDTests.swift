import Testing
@testable import ManuscriptKit

@Test func objectIDRejectsShortHex() {
    #expect(ObjectID(hex: "abc") == nil)
    #expect(ObjectID(hex: String(repeating: "a", count: 40))?.short == "aaaaaaa")
}
