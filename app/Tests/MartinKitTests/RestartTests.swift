import Foundation
import Testing
@testable import MartinKit

struct RestartTests {
    @Test func burstOfChangesRestartsOnce() async throws {
        let queue = DispatchQueue(label: "restart-tests")
        nonisolated(unsafe) var attempts = 0
        let restart = Restart(queue: queue) {
            attempts += 1
            return true
        }
        queue.sync {
            for _ in 0..<5 { restart.schedule(after: 0.05) }
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(queue.sync { attempts } == 1)
    }
}
