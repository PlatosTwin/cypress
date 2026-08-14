// Package migrations holds the numbered SQL files and nothing else.
//
// It exists as its own package purely so the files can live at `server/migrations/` — Go's `embed`
// cannot reach into a parent directory, so the alternative was burying them under
// `internal/store/`, where they are much less obviously the deployment-critical artifact they are.
//
// The runner is `internal/store/migrate.go`. The rules it enforces are stated there; the one that
// matters when adding a file here is that **an applied migration is frozen**. Change behaviour by
// adding `00N_whatever.sql`, never by editing a file that has run somewhere.
package migrations

import "embed"

// Files holds every `NNN_name.sql` in this directory.
//
// The pattern is deliberately not `*` — a stray `.md`, a `.bak` left by an editor, or this file
// itself must not be mistaken for a migration by a runner that parses whatever it is handed.
//
//go:embed *.sql
var Files embed.FS
