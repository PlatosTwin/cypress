import Foundation

/// A run of contributions read from the store, and whether it is the whole of them.
///
/// The type exists because a payload of bare arrays cannot say which of the two it is holding, and
/// a page's `count` reads exactly like a total (ERRATA E38). `TreeProfile.photos` was `LIMIT 30`
/// and screen 03 printed `30 photos · since 2024` for a tree with 214 photographs going back to
/// 2019 — both numbers wrong, both plausible, and nothing in the types to catch it.
///
/// So the count is the thing this type withholds. There is no `count` and no `Collection`
/// conformance: the rows in hand are `items`, which is a truthful name for them whatever the read
/// did, and the size of the series is `totalCount`, which is `nil` unless the read actually
/// returned all of it. A caller that wants to print a number has to handle the nil, and the only
/// way to make it non-nil is to read the series whole.
public struct Series<Element: Hashable & Sendable>: Hashable, Sendable {

    /// The rows this read returned. Ordering is the query's, not this type's.
    public let items: [Element]

    /// Whether `items` is the series or a page of it.
    ///
    /// Set by whoever ran the query, from the query — never assumed. `ContributionStore` proves it
    /// by asking for one row more than the caller wanted and seeing whether that row exists.
    public let isComplete: Bool

    /// The whole series, from a read that had no limit on it.
    public init(complete items: [Element]) {
        self.items = items
        self.isComplete = true
    }

    /// A read that may or may not have exhausted the series.
    public init(items: [Element], isComplete: Bool) {
        self.items = items
        self.isComplete = isComplete
    }

    public static var empty: Series<Element> { Series(complete: []) }

    /// How many rows the series has — `nil` when this is only a page of it.
    ///
    /// Anything user-visible that counts (`214 photos`, A8's `Six people know this tree`) reads
    /// this and renders nothing when it is nil. Rendering a page's size as a total is the bug this
    /// type is here to make unwritable.
    public var totalCount: Int? { isComplete ? items.count : nil }

    /// A filtered view that keeps the completeness it started with.
    ///
    /// Filtering a whole series leaves a whole series — every row that the predicate would have
    /// admitted was in hand to be tested. Filtering a page leaves a page, for the same reason.
    public func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> Series<Element> {
        Series(items: try items.filter(isIncluded), isComplete: isComplete)
    }

    /// The same rows in another order. Ordering says nothing about completeness.
    public func sorted(by areInIncreasingOrder: (Element, Element) throws -> Bool) rethrows -> Series<Element> {
        Series(items: try items.sorted(by: areInIncreasingOrder), isComplete: isComplete)
    }
}
