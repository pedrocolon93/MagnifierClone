import Foundation
import Testing
@testable import MagnifierClone

@MainActor
struct WaitingFeedbackTests {
    final class Counter { var count = 0 }

    private func make() -> (WaitingFeedback, Counter) {
        let counter = Counter()
        return (WaitingFeedback(ding: { counter.count += 1 }), counter)
    }

    @Test func startDingsImmediately() {
        let (feedback, counter) = make()
        feedback.start(interval: 1.0)
        #expect(counter.count == 1)
        feedback.stop()
    }

    @Test func repeatsAtInterval() async throws {
        let (feedback, counter) = make()
        feedback.start(interval: 0.1)
        try await Task.sleep(for: .seconds(0.35))
        feedback.stop()
        #expect(3...5 ~= counter.count)
    }

    @Test func stopHaltsDings() async throws {
        let (feedback, counter) = make()
        feedback.start(interval: 0.1)
        feedback.stop()
        let after = counter.count
        try await Task.sleep(for: .seconds(0.3))
        #expect(counter.count == after)
    }

    @Test func stopWhenNotRunningIsHarmless() {
        let (feedback, counter) = make()
        feedback.stop()
        feedback.stop()
        #expect(counter.count == 0)
    }

    @Test func restartDoesNotDoubleSchedule() async throws {
        let (feedback, counter) = make()
        feedback.start(interval: 0.1)
        feedback.start(interval: 0.1)
        try await Task.sleep(for: .seconds(0.35))
        feedback.stop()
        #expect(counter.count <= 6)
    }
}
