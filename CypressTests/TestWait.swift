import Foundation
import Testing
@testable import Cypress

/// The one way the map suites wait for a `MapModel`, and the one way they report a wait that failed.
///
/// THE RULE. A map test waits for the model's own work, never for a wall clock. ``settle(_:rounds:sourceLocation:until:)``
/// checks the condition, then awaits each task the model holds (`MapModel.outstandingTasks`) and
/// checks again after each one. When every task has finished and the model has started no new one,
/// the model is idle, and a condition that is still false is a failure at once: the model settled
/// on the wrong answer, and no amount of extra time would change it. The message says exactly that.
///
/// WHY NOT A WALL CLOCK. Until ROADMAP item 108, five suites polled their condition against a
/// 90-second ceiling. CI runs about 2,100 Swift Testing tests in parallel on a 3-core runner, and a
/// test's tasks queue on the shared cooperative pool behind every other test's work. That queue
/// time counted against the ceiling. On run 43495993786, three `MapSearchTests` tests each "failed
/// after 102" seconds at their waits; one waited only for `model.search.isActive`, which the model
/// sets after a 300 ms debounce and a catalog read. All three passed on the re-run. That is a
/// starved runner, and a wall clock cannot tell it apart from a model that never settles. Awaiting
/// the tasks can: a slow task is waited out however long the queue is, and a model that settles on
/// the wrong answer fails as soon as it is idle.
///
/// WHY ONE HELPER. The five suites each had a private `waitUntil` copy. An earlier version of this
/// file explains the cost of copies: two of three **returned silently** on a timeout, so CI run
/// 30850154829 reported eighteen issues and not one said "timed out". Every wait now goes through
/// this file, and every failure names the line that was waiting.
///
/// WHAT IS STILL NOT PROVED HERE. A task that never finishes (a fake API that never answers) makes
/// `settle` wait forever, the same as any `await`. No map suite has such a fake today. Each of the
/// five suites that call `settle` carries `.timeLimit(.minutes(5))`, so a real hang fails that test
/// in minutes rather than running the unit job to its own timeout. Five minutes is about three times
/// the longest starved wait seen in CI (102 s, run 43495993786), so only a hang reaches it.
enum TestWait {

    /// How many await-and-check rounds ``settle(_:rounds:sourceLocation:until:)`` runs before it
    /// calls the model busy for good. One round awaits every task the model held at its start. A
    /// typed query needs two: the search task, then the fetch it schedules. Twenty is far more than
    /// the longest chain in `MapModel`, so reaching it means the model keeps starting work.
    static let settleRounds = 20

    /// Waits until `condition` holds or `model` is idle with it false, and records the second case
    /// as a failure at `sourceLocation`.
    ///
    /// The condition is checked after **each** task, not only after a whole round. That matters
    /// for the `Needs care` toast: a finished fetch shows it and starts its dismissal task, and a
    /// test waiting for the toast to show must stop there, before the dismissal is awaited.
    ///
    /// `sourceLocation` defaults to the caller's line, so the issue names the line that was
    /// waiting instead of this file.
    @MainActor
    static func settle(
        _ model: MapModel,
        rounds: Int = settleRounds,
        sourceLocation: SourceLocation = #_sourceLocation,
        until condition: () -> Bool
    ) async {
        for _ in 0..<rounds {
            if condition() { return }
            let before = model.outstandingTasks
            for task in before {
                await task.value
                if condition() { return }
            }
            // Every task in `before` has finished. If the list is the same, nothing started new
            // work while they ran, so the model is idle and the answer is final.
            if model.outstandingTasks == before {
                Issue.record(
                    """
                    the model settled with the condition false: every task it started has \
                    finished, and it started no new one
                    """,
                    sourceLocation: sourceLocation
                )
                return
            }
        }
        if condition() { return }
        Issue.record(
            "the model never went idle: it was still starting new tasks after \(rounds) rounds",
            sourceLocation: sourceLocation
        )
    }
}
