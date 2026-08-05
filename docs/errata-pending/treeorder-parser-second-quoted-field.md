## `treeOrder`'s label parser mis-split a focused `TextField`'s second quoted field (task #221)

**Found while building `CypressUITests/ReadingOrderAccessibilityTests`, screen 01's map test.**

`DeepLinkHarness.treeOrder(_:)` (added for E117, extended by E118) parses `debugDescription` lines
by finding `label: '` and then taking the line's *last* single quote as the closing delimiter — a
design that was correct for every case on record, including a label that itself embeds a quoted
phrase (a cultivar name in scare quotes, `testTreeOrderParserReportsAnInvertedTree`'s own fixture),
because nothing after the label was ever quoted too.

A focused `TextField` breaks that premise. Live output:

```
TextField, 0x10606a170, {{16.0, 70.0}, {408.0, 43.7}}, label: 'Search', placeholderValue: 'Search a species…', value: cypress, Keyboard Focused
```

`placeholderValue` is a second quoted field *after* the label, so "the line's last quote" belongs to
it, not to the label. The old parser read this line's label as
`"Search', placeholderValue: 'Search a species…"` — two fields mashed into one string — rather than
`"Search"`. Nothing before this ticket exercised `treeOrder` against a focused text field's own
`debugDescription` line, so nothing had found it.

**The fix:** the label's closing quote is now the first `'` immediately followed by `, ` (the start
of the next field), searched from where the label opens — falling back to the line's last quote when
no such boundary exists, which covers every previously-working case (a label with nothing after it,
and a label with embedded quotes and nothing after it). Verified against all of the above, plus the
new `TextField` case, in the extended `testTreeOrderParserReportsAnInvertedTree`.

Nothing else in the shipped suite was exercising this path — `DeepLinkSweepTests`' own use of
`treeOrder` only reads pushed screens, none of which hold a focused text field — so this is a latent
defect in shared infrastructure being fixed on the way past, not a regression of anything that had
been asserting against it.
