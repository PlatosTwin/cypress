# F27 — a reading can be taken back.
#
# Checked against the code and against a run on an iPhone 16 Pro, not against the ticket:
#   - `Cypress/Data/Store/AppSchema.swift` v21 — `outbox.kind` learns `measurement_withdrawal`
#   - `Cypress/Data/API/LocalAPI.swift` — `withdrawMeasurement` tombstones and queues in one write
#   - `Cypress/Features/GrowthHistory/GrowthHistoryView.swift` — the control on the log row
#   - `CypressTests/MeasurementWithdrawalTests` — the six surfaces that stop counting it
#
# Every line below is about this phone's own record, which is what a tester can check and what is
# true whatever the service does.
#
# **A line about the sync queue was here and has been taken out.** It read "The withdrawal joins the
# sync queue under its own name, so you can see it waiting alongside everything else." The row is
# queued under its own name — that part is real — but the service does not accept the kind yet, and
# `validation_failed` is non-retryable, so on a build that talks to the service the row goes to
# `failed` on its first attempt and stays red on screen 17. A tester reading that sentence would
# have watched the opposite of it happen. The replacement is silence rather than a warning about a
# red row, because the server change is a round of its own and this note must be true either way:
# said now, a warning would be false the moment that change deploys, which is the same defect
# pointing the other direction.

On the growth screen, each reading you contributed now has a control to withdraw it.
Tapping it asks first, and says what withdrawal does before anything happens.
A withdrawn reading comes off both growth charts, out of the measurement log, out of your journal and out of your grove counts.
Withdrawing the only reading of its kind on a tree removes that chart, and the confirmation says so before you tap.
Readings contributed on another phone, and readings left behind by a deleted account, have no control — they are not yours to take back.
