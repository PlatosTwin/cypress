### E?? — Two shipped sentences promise a community reviewer, and beta has no way to reach one

Found while writing #125's copy, on the same test #125's notice had to pass. **Flagged, not changed**
— both sentences are the operative words of a ruling and an errata that are not this ticket's to
edit, and rewriting shipped copy on somebody else's decision from a branch is how two live branches
end up disagreeing about what a screen says.

#### The sentences

- `CheckInCopy.reviewNotice` — screen 05, under both flagging segments:
  *"This goes to a community reviewer to confirm. The city is not notified."* (E170.)
- `TreeProfileCopy.reportSpeciesNotice` — the species report control on the tree profile:
  *"This goes to a community reviewer. The city is not notified."* (R45.)

`ReviewFlagNoticeTests` asserts the first as a property of the words, so it is pinned as well as
shipped.

#### Why they are the same defect class as the claim they were written to avoid

Each sentence was written to replace *"sent to the city"*, and the replacement is right about the
city. The second half of each is the problem: **there is no contribution sync.** #158 is unbuilt and
unscheduled. The outbox drains through `APIOutboxTransport` into `LocalAPI`, which writes this
phone's own tables; nothing uploads and nothing downloads anybody's rows, and beta is about five
people with no accounts. A flag raised on one phone is visible to that phone and to no other.

DECISIONS §3 constraint 3 forbids "sent to the city" because it promises a destination the report
does not reach; D16(a) made that permanent. "Goes to a community reviewer" promises a destination the
report does not reach either. The noun differs; the defect does not.

It is not *entirely* untrue — a lead on this same phone can resolve the flag, and in the beta the
role is granted through the You tab's DEBUG affordance. But "a community reviewer" is read by a
person as *somebody else, elsewhere*, and that person does not exist.

#### The register that is available

#125 built and shipped one, on a control two hundred points below the species sentence:

> This is kept on this phone and shows on this record. The city is not notified, and Cypress cannot
> yet carry a report to anybody else's phone.

Says where the report stays, says what it does there, then states both limits. E126's rule is why the
second half is spoken rather than left silent.

**The cost of leaving this open is a screen that contradicts itself.** The tree profile now carries
both registers in one column: the species control says a community reviewer, and the record control
three lines down says nothing can reach anybody else's phone. Whoever owns R45's and E170's words
should decide which is true, and it is not both.

#### What a fix is

Three strings and their two tests. `CheckInCopy.reviewNotice`, `CheckInCopy.reviewConfirmMessage` and
`TreeProfileCopy.reportSpeciesNotice`, plus the `contains("community reviewer")` assertions in
`ReviewFlagNoticeTests` — which should invert rather than relax, since the claim is now the thing
being guarded against. `ModerationCopy`'s messages were checked and are clean: they say the city is
not notified and claim no other reader.
