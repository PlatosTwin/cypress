# `internal:` and not the obvious sentence. The tokens are exported FROM the shipped Swift, so
# nothing a tester sees changes: the app already renders from the declarations this reads. The CSS
# has no consumer yet — the page that will use it is milestone W-C, unwritten — and no Swift
# changed, so no tester's build moves. The line belongs to whatever first renders with it.

internal: the design tokens are exported from the Swift declarations to CSS, with a test that fails when the export and its source disagree. Nothing renders from them yet.
