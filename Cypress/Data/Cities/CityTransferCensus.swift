import Foundation

/// How much work this app did over a transferred city file — **counted, never timed**.
///
/// ── Why this type exists ──────────────────────────────────────────────────────────────────────
///
/// The transfer's original defect (tester report, build 49, 2026-08-23: *"Download is super slow"*)
/// was a per-byte walk of the response — `for try await byte in session.bytes(…)`, one loop
/// iteration per byte of a 199 MB pack. The guard written against its return raced two wall-clock
/// measurements and required the real transfer to beat a per-byte control by 6×.
///
/// **That guard flaked on CI three times with no code change**, which is what this type replaces:
///
///   * 2026-08-23 — 8.5× measured against the then-10× threshold.
///   * PR #123's fix round narrowed a sibling window the same way, and the review flagged the class.
///   * 2026-08-31, run 33430972054 (the build-65 main run) — `elapsed × 6 = 37.698` against a
///     control of `11.744`. A plain rerun went green.
///
/// A wall-clock ratio on a shared runner measures the runner. What the margin was ever a proxy for
/// is a **count**: a per-byte walk performs one operation per byte, a chunked path performs one per
/// `CityDownloader.chunkSize`. On the 4 MiB fixture that is 4,194,304 against 8 — five orders of
/// magnitude apart, deterministic, and unmoved by whatever else the machine is doing.
///
/// ── What it counts, and what it therefore cannot see ──────────────────────────────────────────
///
/// Two facts, and they cover the defect from both sides. Neither is sufficient alone:
///
/// 1. `fileHandoffs` — every time URLSession handed this app a **finished file** it holds a promise
///    for (`didFinishDownloadingTo`). This is the fact that makes a per-byte walk of the *response*
///    unrepresentable: the app is given a URL, never a byte stream. Without it the read count below
///    stays perfectly small while the original defect runs, because a transfer that accumulates the
///    body one byte at a time and *then* writes a file is still verified in tidy 512 KiB chunks.
/// 2. `payloadReads` / `payloadBytesRead` — the reads this app performs over those bytes, which
///    today is exactly `CityDownloader.verifiableFacts`' hashing loop. This is the fact that catches
///    the same defect one layer down: a chunk size of one byte walks the transferred bytes just as
///    surely, and the handoff count is oblivious to it.
///
/// **It counts the two sites it is wired to, and nothing else** — stated this way after review
/// finding F2, which caught the previous sentence claiming the gap was `FileManager`. That was
/// narrower than the truth and therefore worse than saying nothing: the real limit is that **a new
/// read site anywhere in the download path counts as zero.** The reviewer demonstrated it with a
/// `FileHandle` opened in `didFinishDownloadingTo` and walked with `read(upToCount: 1)` — 4.2
/// million single-byte reads of the payload, a ~10× slowdown of exactly the reported shape, and all
/// four guards green. `FileManager` is one instance of that (staging and installing are `moveItem`,
/// renames that read no byte, so a path that *copied* would be invisible), not the whole of it.
///
/// **So the invariant this design leans on is enforced rather than assumed.** What makes the two
/// counters sufficient is that `CityDownloader.verifiableFacts` is the app's only contact with a
/// transferred file's bytes, and that was a comment until F2. `CityDownloadsFeedbackTests`'
/// source gate now bounds `FileHandle(forReadingFrom:` and `read(upToCount:` to exactly one
/// occurrence each, in `CityDownloader.swift`, and forbids the streaming read APIs outright across
/// the whole directory. A new read site fails that gate, and the message tells its author to bring
/// a counter with it.
///
/// ── Cost, and why it is per-instance ──────────────────────────────────────────────────────────
///
/// Nothing in a shipping launch constructs one: `CityDownloadService.init` and
/// `CityDownloader.verify` both default their parameter to `nil`, so the app pays one nil check per
/// 512 KiB chunk and one per finished transfer.
///
/// **Handed in rather than global**, which is not fastidiousness. Swift Testing runs suites in
/// parallel, and a process-wide counter would be written by every concurrent transfer in the suite
/// — a guard whose reading depends on what the neighbouring test happens to be doing is the
/// wall-clock defect wearing a different hat.
final class CityTransferCensus: @unchecked Sendable {

    /// One reading. A value, so a test compares a snapshot rather than racing the counters.
    struct Counts: Equatable, Sendable {
        /// Finished files URLSession handed this app for a transfer it holds a promise for.
        var fileHandoffs = 0
        /// Reads this app performed over a transferred file's bytes, each returning a non-empty
        /// chunk. One per `CityDownloader.chunkSize`; one per **byte** if the defect returns.
        var payloadReads = 0
        /// The bytes those reads returned. Present so a low `payloadReads` cannot be mistaken for a
        /// chunked read when it is really a read that never happened.
        var payloadBytesRead: Int64 = 0
    }

    private let lock = NSLock()
    private var state = Counts()

    init() {}

    /// A snapshot. Taken under the lock, so the three numbers describe one moment.
    var counts: Counts {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    func recordFileHandoff() {
        lock.lock()
        state.fileHandoffs += 1
        lock.unlock()
    }

    func recordPayloadRead(bytes: Int) {
        lock.lock()
        state.payloadReads += 1
        state.payloadBytesRead += Int64(bytes)
        lock.unlock()
    }
}
