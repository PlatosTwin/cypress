# F27 — a reading can be taken back.
#
# Checked against the code and against a run on an iPhone 16 Pro, not against the ticket:
#   - `Cypress/Data/Store/AppSchema.swift` v21 — `outbox.kind` learns `measurement_withdrawal`
#   - `Cypress/Data/API/LocalAPI.swift` — `withdrawMeasurement` tombstones and queues in one write
#   - `Cypress/Features/GrowthHistory/GrowthHistoryView.swift` — the control on the log row
#   - `CypressTests/MeasurementWithdrawalTests` — the six surfaces that stop counting it
#
# The last line is here because it is true and because `AccountDeletionCopy` sets the rule that a
# claim about reach is made carefully: the withdrawal is queued like every other contribution, and
# what the service does with it is the service's round, not this one.

On the growth screen, each reading you contributed now has a control to withdraw it.
Tapping it asks first, and says what withdrawal does before anything happens.
A withdrawn reading comes off both growth charts, out of the measurement log, out of your journal and out of your grove counts.
Withdrawing the only reading of its kind on a tree removes that chart, and the confirmation says so before you tap.
Readings contributed on another phone, and readings left behind by a deleted account, have no control — they are not yours to take back.
The withdrawal joins the sync queue under its own name, so you can see it waiting alongside everything else.
