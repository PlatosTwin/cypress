package store

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/uuid"
)

// applyDispute raises one dispute and returns nothing but a fatal on failure.
func applyDispute(t *testing.T, store *Store, dispute, tree uuid.UUID, owner Owner) {
	t.Helper()
	_, err := store.Apply(context.Background(), Mutation{
		ClientUUID: uuid.New(), Kind: "data_dispute", TreeUUID: tree,
		Payload: json.RawMessage(`{"id":"` + dispute.String() + `","treeID":"` + tree.String() +
			`","treeSource":"city","issues":["wrong_species"]}`),
		OccurredAt: time.Now().UTC(),
	}, owner)
	if err != nil {
		t.Fatalf("raising the dispute: %v", err)
	}
}

// withdrawDispute drains one `data_dispute_withdrawal` and returns Apply's error unread.
func withdrawDispute(t *testing.T, store *Store, dispute, tree uuid.UUID, owner Owner) error {
	t.Helper()
	_, err := store.Apply(context.Background(), Mutation{
		ClientUUID: uuid.New(), Kind: "data_dispute_withdrawal", TreeUUID: tree,
		Payload: json.RawMessage(`{"disputeID":"` + dispute.String() + `","treeID":"` +
			tree.String() + `"}`),
		OccurredAt:         time.Now().UTC(),
		WithdrawnDisputeID: &dispute,
	}, owner)
	return err
}

// TestAnAnonymizedDisputeIsWithdrawableByNobody pins the arm of `disputeIsThisIdentitys` that no
// handler test can reach: a dispute whose owner columns have both been cleared.
//
// `AccountDeletionChoice.leaveRecords` is the door that produces it — the record stays on the tree
// with the name taken off — and the rule it implies is that a record owned by nobody is not
// withdrawable by anybody. The query gets there by arithmetic rather than by a branch: the row is
// counted by `count(*)` and not by the `FILTER`, so `matched > 0` and `mine == 0`, which is the
// refusal.
//
// **The control is the second half and it is not decoration.** "Here and nobody's" has to be
// distinguishable from "not here at all", because those two states take opposite answers — a
// withdrawal naming a dispute this service never held is a *success*, and a test that only checked
// the refusal would pass just as happily if the lookup had stopped finding anything at all.
func TestAnAnonymizedDisputeIsWithdrawableByNobody(t *testing.T) {
	store := testStore(t)
	user := makeUser(t, store, "apple-sub-dispute-anonymized")
	_, deviceID := makeDevice(t, store)
	dispute, tree := uuid.New(), uuid.New()

	applyDispute(t, store, dispute, tree, UserOwner(user.ID))
	if _, err := store.DeleteAccount(context.Background(), user.ID, LeaveRecords, nil, ""); err != nil {
		t.Fatalf("deleting the account: %v", err)
	}

	var userID, deviceIDColumn *uuid.UUID
	if err := store.pool.QueryRow(context.Background(), `
		SELECT user_id, device_id FROM contributions WHERE kind = 'data_dispute'
	`).Scan(&userID, &deviceIDColumn); err != nil {
		t.Fatalf("reading the anonymized dispute back: %v", err)
	}
	if userID != nil || deviceIDColumn != nil {
		t.Fatalf("the dispute still has an owner (user_id=%v device_id=%v); leaveRecords is "+
			"supposed to have cleared both, and this test measures nothing without that",
			userID, deviceIDColumn)
	}

	if err := withdrawDispute(t, store, dispute, tree, DeviceOwner(deviceID)); !errors.Is(err, ErrDisputeNotOwned) {
		t.Fatalf("withdrawing an anonymized dispute = %v, want ErrDisputeNotOwned — a record owned "+
			"by nobody is not withdrawable by anybody", err)
	}

	// The control: the same identity, a dispute id nothing here holds. Success, because the raise
	// may still be in that phone's outbox — see `disputeIsThisIdentitys`.
	if err := withdrawDispute(t, store, uuid.New(), tree, DeviceOwner(deviceID)); err != nil {
		t.Fatalf("withdrawing a dispute this service never held = %v, want success — the refusal "+
			"above is about the row it found, not about the identity asking", err)
	}
}
