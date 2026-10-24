import Foundation
import Testing
@testable import MagnifierClone

@Test func waitingSoundIsBundled() {
    #expect(Bundle.main.url(forResource: "waiting", withExtension: "m4a") != nil)
}
