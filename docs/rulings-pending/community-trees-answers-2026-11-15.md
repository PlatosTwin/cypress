# Rulings pending: the owner's answers of 2026-11-15 (community trees: old trees, and the C3 screens)

Unnumbered, per CLAUDE.md "Numbering and shared files". The orchestrator splices it at merge. No code
comment cites this filename.

Every answer below is the owner's, given in an AskUserQuestion dialog on 2026-11-15. Each string in
quotation marks is the exact string the owner saw and chose. Nothing here is built by this file. It
adds to `community-trees-old-trees.md` and `community-trees-c3-answers.md` (both 2026-11-14), and it
changes one answer in the second of them, as stated below.

Answers of the same day that a code branch records are not repeated here: where the "ALREADY ON
RECORD" note sits, what a tap on its rows does, and when it shows and hides (the phone half of
ROADMAP 140); a phone that never registered, the cache limit, and the zoom at which community trees
download (C2); the day a community tree shows as added (the service piece of ROADMAP 139).

---

### R??? — Old community trees: the add photo, the refused adds, and the Outbox rows (ROADMAP 139)

1. **The photo taken on the Add this tree screen.** The round that planned 139 found that this photo
   has never been sent to the service, for any tree, new or old. Offered: "Every tree, new and old
   (Recommended)"; "Old trees only for now"; "Do not send it". **Chosen: "Every tree, new and old".**
   Each community tree sends its add photo, in this round. Location and time data are stripped from
   the file first. Other people see the tree with its photo.
2. **Adds the service refused under the old 10 m rule.** Those trees are on their adders' phones
   with a failed row on the Outbox screen, and the rule is gone
   (`community-trees-no-proximity-rule.md`). Offered: "Yes, retry once (Recommended)"; "Leave them".
   **Chosen: "Yes, retry once".** After the update, the app sends each such tree again once, with no
   question, with everything recorded on it.
3. **How the backlog shows on the Outbox screen.** Offered: "Ordinary rows (Recommended)"; "One
   summary row"; "Hidden unless one fails". **Chosen: "Ordinary rows".** Each item is its own row
   with today's labels, like anything else waiting to be sent. No new wording.

### R??? — Species answers on a community tree someone else added (changes an answer of 2026-11-14)

**What changed.** On 2026-11-14 the owner chose "add the species controls" for the profile of a tree
someone else added (`community-trees-c3-answers.md`, "Other people's community trees", answer 2).
The option text said that other people could fix a wrong name. That was the orchestrator's error:
the service keeps a non-adder's species statement and applies it to nobody, and the phone refuses
the two species verbs on a tree the reader did not add. The owner was told and asked again.

1. **What should happen when a person names the species of a tree someone else added.** Offered:
   "Show it on your phone (Recommended)"; "Make it count for everyone"; "Only report a wrong
   species". **Chosen: "Make it count for everyone".** It needs a service change, so it is not in
   the next build.
2. **The next build.** Offered: "Hide species controls for now (Recommended)"; "Phone-only for now".
   **Chosen: "Hide species controls for now".** The profile of a tree someone else added shows
   neither "Say what species you think this is" nor "Report the species as wrong". Both come back
   when the service change is built. This replaces answer 2 of 2026-11-14 for the next build; the
   rest of that answer stands (visit, check-in, care, favorite, share, and measure show, and Move
   pin never does).
3. **The later rule for a tree with no species.** Offered: "It names the tree for everyone
   (Recommended)"; "It waits for the adder". **Chosen: "It names the tree for everyone".** The first
   answer becomes the tree's species for everyone, marked "species named by a contributor". The
   adder can still correct it.
4. **The later rule for a tree that has a species.** Offered: "Keep the name, mark it questioned
   (Recommended)"; "The newest answer wins". **Chosen: "Keep the name, mark it questioned".** The
   species stays. The profile shows the line it already has for a reported species, "Somebody has
   reported this species as wrong." The adder can correct the species, and so can the operator.

Rules 3 and 4 are a service change and a phone change that no round has planned. Its ROADMAP chip is
added by the C3 round, which builds answer 2.

### R??? — The square on a history row, and the note when the phone does not know the sharing answer

1. **The square at the left of a history row.** The profile's activity rows and the Journal's rows
   each start with a square; a history row ("Added", "Pin moved · 12 m north", and the Journal's
   "Moved the pin of X") had none decided. Offered: "The community tree mark (Recommended)"; "A plain
   empty square"; "The Care leaf tile". **Chosen: "The community tree mark"**: the map's dashed green
   ring on its pale fill, drawn small.
2. **When the phone does not know whether the person agreed to share tree records.** This happens
   after a reinstall, and for an account from before the answer was saved. Offered: "Keep today's
   note (Recommended)"; "Treat it as sharing"; "Treat it as not sharing". **Chosen: "Keep today's
   note".** The Add this tree note reads "Recorded as community-added and unverified, on this
   phone." as it does today. The profile shows no "only on this phone" line unless the service says
   the tree is not shared.

---

#### What these answers do not settle (facts for the rounds that build them, not rulings)

- **A signed-in reader who declined to share.** The approved strings say "…after you agree to share
  your tree records." The C3 planner could not find a control that lets such a reader agree later.
  Verify it, and if there is none, ask the owner.
- **Photos sent since syncing began.** The retry in answer 2 of the first entry, and the send of old
  records, must not send a second copy of a photograph the service already has. The service matches
  rows on `client_uuid`; check what it does for a photograph before sending one again.
- **When the next build ships.** The owner's words: "plan is that once you finish this whole round
  and it's all set, we'll release the next build". The round is ROADMAP 140, C2, C3, and ROADMAP
  139. That sentence names when; the release itself still needs the owner's go-ahead.
