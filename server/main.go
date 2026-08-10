// Command cypress-sync is the live-layer sync API (ticket #158, RULINGS R72).
//
// It replaces the R36 placeholder that answered 501 to everything. One `shared-cpu-1x`/256 MB
// machine on the `cypress-sync` Fly app, Postgres, two direct Go dependencies, a static binary.
//
// ── What this service is and is not ────────────────────────────────────────────────────────────
//
// R36 rules which layer travels which way and R72 does not reopen it. The city layer — the map's
// pan loop, species, the almanac — is answered on the phone from the installed city file and never
// reaches here. What this service holds is the community layer and the account's own rows: the
// things liveness actually buys, and the things a second device cannot know without it.
//
// ── Configuration ──────────────────────────────────────────────────────────────────────────────
//
// Every value that matters comes from the environment and **none of those has a default**. A
// missing one is a refusal to start, which is the only safe answer: a service that booted without
// `SESSION_SIGNING_KEY` would mint forgeable sessions and look perfectly healthy doing it.
//
// Two do fall back, and they are named here so the sentence above is not quietly false: `PORT` to
// `8080` and `GIT_SHA` to `"unknown"` (see `envOr`). Neither is a credential and neither changes
// behaviour — one is what Fly sets anyway, the other only labels `/health`.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/PlatosTwin/cypress/server/internal/api"
	"github.com/PlatosTwin/cypress/server/internal/apple"
	"github.com/PlatosTwin/cypress/server/internal/storage"
	"github.com/PlatosTwin/cypress/server/internal/store"
	"github.com/PlatosTwin/cypress/server/internal/tokens"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	if err := run(log); err != nil {
		log.Error("fatal", "cause", err)
		os.Exit(1)
	}
}

// appleAuth joins the verifier and the token client into the one interface the handlers take.
type appleAuth struct {
	*apple.Verifier
	*apple.Client
}

func run(log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	databaseURL, err := required("DATABASE_URL")
	if err != nil {
		return err
	}
	signingKey, err := required("SESSION_SIGNING_KEY")
	if err != nil {
		return err
	}
	signer, err := tokens.NewSigner([]byte(signingKey))
	if err != nil {
		return err
	}

	appleConfig := apple.Config{
		TeamID: os.Getenv("APPLE_TEAM_ID"),
		KeyID:  os.Getenv("APPLE_KEY_ID"),
		// Read as-is. The `.p8` arrives as its full PEM text, newlines and all; `apple` restores
		// literal `\n` sequences as a tolerance for a secret store that flattened them, but nothing
		// here requires base64 or any other pre-encoding.
		PrivateKeyPEM: os.Getenv("APPLE_PRIVATE_KEY"),
		BundleID:      os.Getenv("APPLE_BUNDLE_ID"),
	}
	if err := appleConfig.Validate(); err != nil {
		return err
	}

	storageConfig := storage.Config{
		AccessKeyID:     os.Getenv("AWS_ACCESS_KEY_ID"),
		SecretAccessKey: os.Getenv("AWS_SECRET_ACCESS_KEY"),
		Endpoint:        os.Getenv("AWS_ENDPOINT_URL_S3"),
		Region:          os.Getenv("AWS_REGION"),
		Bucket:          os.Getenv("BUCKET_NAME"),
	}
	if err := storageConfig.Validate(); err != nil {
		return err
	}

	operatorToken, err := required("OPERATOR_TOKEN")
	if err != nil {
		// Not optional, and this is R72 ruling 5 rather than tidiness: the takedown ships in the
		// same release as auto-approve, and a takedown route with no credential configured is a
		// takedown that cannot be performed.
		return err
	}

	dataStore, err := store.Open(ctx, databaseURL)
	if err != nil {
		return err
	}
	defer dataStore.Close()

	schemaVersion, err := dataStore.SchemaVersion(ctx)
	if err != nil {
		return err
	}
	log.Info("schema up to date", "server_schema_version", schemaVersion)

	verifier, err := apple.NewVerifier(ctx, appleConfig.BundleID)
	if err != nil {
		return err
	}

	server := &api.Server{
		Store:         dataStore,
		Apple:         appleAuth{Verifier: verifier, Client: apple.NewClient(appleConfig)},
		Signer:        signer,
		Presigner:     storage.NewPresigner(storageConfig),
		Log:           log,
		GitSHA:        envOr("GIT_SHA", "unknown"),
		OperatorToken: operatorToken,
	}

	httpServer := &http.Server{
		Addr:              ":" + envOr("PORT", "8080"),
		Handler:           server.Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	// The obligation R72 ruling 2 creates is discharged here, not merely recorded. On boot as well
	// as on a tick, because this machine stops when idle and spends most of its life stopped.
	go api.RunAppleRevocationDrain(ctx, dataStore, server.Apple, log)

	go func() {
		<-ctx.Done()
		// The machine stops when idle (`auto_stop_machines`), so a graceful shutdown is not a
		// nicety here — it is the normal path, several times a day.
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if err := httpServer.Shutdown(shutdownCtx); err != nil {
			log.Error("shutdown", "cause", err)
		}
	}()

	log.Info("listening", "addr", httpServer.Addr, "git_sha", server.GitSHA)
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

func required(name string) (string, error) {
	value := os.Getenv(name)
	if value == "" {
		return "", fmt.Errorf("%s is not set", name)
	}
	return value, nil
}

func envOr(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}
