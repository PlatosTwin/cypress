// PLACEHOLDER — R36 live-layer scaffolding, ticket #158.
//
// This is NOT the sync API. It exists only to prove the Fly app, machine, region and
// Tigris bucket are provisioned and reachable. #158 is spec-first: the real stack
// decision (Go / Node / Fastify / something else) is explicitly still open, and this
// file is expected to be deleted or rewritten wholesale when #158 lands.
//
// GET /health -> 200, JSON naming the git sha, with "placeholder": true
// anything else -> 501, JSON saying the sync API is not built yet
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
)

func writeJSON(w http.ResponseWriter, status int, body map[string]any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(body); err != nil {
		log.Printf("encode error: %v", err)
	}
}

func main() {
	sha := os.Getenv("GIT_SHA")
	if sha == "" {
		sha = "unknown"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":      "ok",
			"service":     "cypress-sync",
			"git_sha":     sha,
			"placeholder": true,
			"ticket":      "#158",
		})
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusNotImplemented, map[string]any{
			"error":       "not_implemented",
			"message":     "The Cypress sync API is not built yet. This is R36 scaffolding only; the API is ticket #158.",
			"placeholder": true,
			"ticket":      "#158",
		})
	})

	log.Printf("placeholder server listening on :%s (git_sha=%s)", port, sha)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}
