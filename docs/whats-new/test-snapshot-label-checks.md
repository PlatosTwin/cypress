# `internal:` because only UI tests changed. Two accessibility checks now read labels from one
# snapshot of the element tree; the rules they check and the app are unchanged.

internal: the "every control is labeled" and "nothing is announced twice" UI checks read labels from one snapshot of the tree instead of querying each element in turn.
