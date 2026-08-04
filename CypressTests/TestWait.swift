import Foundation
import Testing

/// The one ceiling the map suites wait under, and the one way they report running out of it.
///
/// WHY THIS IS SHARED. Three suites had each grown a private `waitUntil` with its own copy of the
/// same loop and the same 20-second ceiling, and two of the three **returned silently** when the
/// ceiling ran out. A timeout therefore surfaced as whatever assertion happened to come next —
/// `speciesIDs → nil`, `(before → 0) > 0`, `rows.count → 0 >= 2` — none of which mention waiting.
/// CI run 30850154829 failed with eighteen issues across three suites and not one of them said
/// "timed out", which is why it read as eleven unrelated logic defects instead of one slow machine.
///
/// WHY THE CEILING IS GENEROUS, AND WHY THAT IS NOT A WEAKENED TEST. No test here asserts how fast
/// the app is; the assertions are all about *what* the model settles on. The debounces are tuned
/// for a thumb, so a test that pinned them would fail the day they were retuned — the ceiling only
/// has to outlast the slowest machine that runs the suite. It costs nothing when a test passes: the
/// waiter returns on the poll that sees the condition, not on the deadline.
///
/// WHAT SET IT. Run 30846300488 ran these tests green; run 30850154829 ran them red forty minutes
/// later on a tree that differed by five lines of workflow YAML and not one byte of Swift. The red
/// runner took 327s over the same 1137 unit tests the green one finished in 233s, and every one of
/// the eleven failures was a suite waiting on the debounce-plus-query path against the 103 MB seed.
/// The old ceiling was chosen against a quiet Mac; ``ceiling`` is chosen against a shared runner.
///
/// If a wait ever times out at this ceiling, believe the message rather than the ceiling: 90
/// seconds is not slowness, and the next thing to check is whether the model settles at all.
enum TestWait {

    /// How long a map model gets to settle before the wait is called a failure.
    static let ceiling: Duration = .seconds(90)

    /// Records the timeout in the waiter's own words, so a slow machine never again arrives
    /// disguised as a wrong answer.
    ///
    /// `sourceLocation` is threaded from the test's own `waitUntil` call rather than defaulted
    /// here, so the issue names the line that was waiting instead of the line that does the
    /// waiting — the four call sites in one suite were previously indistinguishable in the log.
    ///
    /// Re-checks the condition before recording anything: a poll loop can lose its last race, and
    /// a condition that is true by the time anyone asks was never a timeout.
    static func timedOut(
        after elapsed: Duration,
        sourceLocation: SourceLocation,
        _ condition: () -> Bool
    ) {
        guard !condition() else { return }
        Issue.record(
            "the model never settled: waited \(elapsed) and the condition was still false",
            sourceLocation: sourceLocation
        )
    }
}
