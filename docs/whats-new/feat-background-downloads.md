# The background-downloads round. One line, because one thing changed for a tester and it is the
# thing two of them reported: "Download fails if app closes or phone screen sleeps" (build 49,
# 2026-08-23).
#
# The sentence names the three states a reader actually notices — leaving the app, the screen
# going dark, the app being closed — rather than the mechanism. `URLSession`, `nsurlsessiond` and
# "background session" mean nothing to somebody who just wants Queens on their phone.
#
# **"Pick up where it left off" is deliberately not in it.** An interrupted transfer does resume
# from the bytes it already had, and saying so would invite the reading that there is a Resume
# button to find. There is not: the resumption is silent and automatic, the row says
# `Downloading…` throughout, and a changelog line promising a control that does not exist is worse
# than one that leaves a good surprise unmentioned. `fix-downloads-feedback.md` made the same call
# about the word "resumable" and it was right.
#
# **The Cancel behavior is not mentioned either.** Cancel still means called off, exactly as it
# always did, so there is nothing for a tester to be told.

City downloads now keep going when you leave the app, when the screen goes dark, and even if the app closes — and a download that was still running is still there when you come back.
