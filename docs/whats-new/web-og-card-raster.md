# `internal:`, and the reason is the same one W-C's own note gave.
#
# The share card the app has been producing since the share sheet shipped now has an image a group
# chat will actually draw — `og:image` is a 1200×630 PNG instead of an SVG no major platform
# decodes, and the page finally tells a crawler the card's type, width and height.
#
# It is `internal:` anyway, because no tester can reach it. Nothing is deployed (W-E), the site's
# domain serves nothing, and `ShareCopy.publicURLPrefix` still points at a hostname that is not the
# owner's — so every link in the wild is as dead today as it was yesterday, and a crawler would have
# to resolve one before any of this is visible. No Swift changed and no build is minted.
#
# (This paragraph named `cypressgrove.app` when it was written. The owner's 2026-09-13 ruling makes
# the domain `cypressatlas.org`; the sentence is now written without a name, because which domain
# serves nothing was never the point of it.)
#
# W-E's note is the one that is not `internal:`.

internal: the OpenGraph share card is rasterized to PNG, so the platforms that refuse SVG can draw it, and the page now declares the card's type and size.
