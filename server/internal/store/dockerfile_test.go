package store

import (
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"testing"
)

// The Dockerfile's COPY list is an allowlist of directories, and an allowlist rots.
//
// `migrations/` was added to the module after the Dockerfile was written, and the first real image
// build failed with `no required module provides package
// github.com/PlatosTwin/cypress/server/migrations`. Nothing in the suite could have caught it: the
// tests compile the module from the worktree, where every directory is present by definition, so
// the only thing that ever exercised the COPY list was `docker build` — which runs on Fly, not here.
//
// This is the cheapest thing that turns "somebody remembers" into "something fails": read the
// Dockerfile, read the tree, compare. It lives in `internal/store` rather than a package of its own
// because that is where the embedded SQL is consumed, and it needs no build machinery at all.
//
// It cannot prove the image builds — only a real build does that. It can prove the one mistake that
// has actually happened cannot happen silently again.

const dockerfilePath = "../../Dockerfile"

// copyLine matches a `COPY` instruction at the start of a line, so a commented one is not a copy.
//
// **Case-insensitive, and that is a correctness fix rather than tidiness.** Docker accepts
// `copy testdata ./testdata`, and an uppercase-only pattern simply did not see it — so a lowercase
// COPY of a test-only path shipped it into the image while `TestDockerfileDoesNotCopyTestOnlyPaths`
// stayed **green**. That is this guard committing the exact defect it was written to catch. It also
// fixes the mirror image, where a lowercase copy of a real package read as "not copied" and gave a
// false red.
//
// `^\s*` because Docker tolerates leading whitespace. A commented line is still not a copy: `#`
// is not whitespace, so `# COPY foo` does not match.
//
// `COPY --from=…` is filtered in code rather than in the pattern: Go's regexp is RE2 and has no
// negative lookahead, and a pattern that silently failed to compile would take the whole package
// down — which is at least loud, but the readable version is better.
var copyLine = regexp.MustCompile(`(?im)^\s*COPY\s+(.+)$`)

// TestDockerfileCopiesEveryPackage is the guard.
func TestDockerfileCopiesEveryPackage(t *testing.T) {
	copied := dockerfileSources(t)

	for _, pkg := range modulePackageDirs(t) {
		if pkg == "." {
			// The main package's files are copied by name rather than as a directory.
			if !slices.Contains(copied, "main.go") {
				t.Error("the Dockerfile does not copy main.go")
			}
			continue
		}
		root := strings.SplitN(pkg, string(filepath.Separator), 2)[0]
		if !slices.Contains(copied, root) && !slices.Contains(copied, pkg) {
			// A top-level package is its own root, so "neither X nor X" would name it twice and
			// read as a bug in the message rather than as a repeated variable. The nested case
			// keeps both, because either COPY would have been a fix.
			missing := "does not copy " + strconv.Quote(root)
			if root != pkg {
				missing = "copies neither " + strconv.Quote(root) + " nor " + strconv.Quote(pkg)
			}
			t.Errorf("the module compiles %q and the Dockerfile %s.\n"+
				"`go build` inside the image will fail with `no required module provides package "+
				"github.com/PlatosTwin/cypress/server/%s`.\nCopied: %v", pkg, missing, pkg, copied)
		}
	}

	for _, required := range []string{"go.mod", "go.sum"} {
		if !slices.Contains(copied, required) {
			t.Errorf("the Dockerfile does not copy %s", required)
		}
	}
}

// TestDockerfileDoesNotCopyTestOnlyPaths is the other direction.
//
// `testdata/` holds the golden wire fixtures. They are read only by tests, which do not run in this
// image, and shipping them would put bytes in a production artifact for no reason.
func TestDockerfileDoesNotCopyTestOnlyPaths(t *testing.T) {
	copied := dockerfileSources(t)
	for _, forbidden := range []string{"testdata", "README.md", "fly.toml"} {
		if slices.Contains(copied, forbidden) {
			t.Errorf("the Dockerfile copies %q, which nothing in the image reads", forbidden)
		}
	}
}

// TestTheDockerfileReaderIsCalibrated runs the parser against a specimen whose answer is known.
//
// CLAUDE.md: calibrate the instrument before trusting the reading. A regex that matched nothing
// would make the guard above pass vacuously — reporting that every package is copied by finding no
// COPY lines at all, which is the exact failure it exists to prevent.
func TestTheDockerfileReaderIsCalibrated(t *testing.T) {
	specimen := `FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
COPY internal ./internal
copy migrations ./migrations
  COPY indented ./indented
# COPY commented ./commented
FROM scratch
COPY --from=build /out/server /server
`
	path := filepath.Join(t.TempDir(), "Dockerfile")
	if err := os.WriteFile(path, []byte(specimen), 0o644); err != nil {
		t.Fatal(err)
	}

	got := sourcesIn(t, path)
	// `migrations` is lowercase and `indented` is whitespace-prefixed: Docker accepts both, so a
	// reader that misses either is a guard with a hole in it. The lowercase case is not
	// hypothetical — it was fail-open here and shipped `testdata/` past the other direction.
	want := []string{"go.mod", "go.sum", "main.go", "internal", "migrations", "indented"}
	for _, expected := range want {
		if !slices.Contains(got, expected) {
			t.Errorf("the reader missed %q in a specimen that copies it: %v", expected, got)
		}
	}
	// It must not pick up the commented line, and must not treat a --from stage copy as a source.
	for _, absent := range []string{"commented", "/out/server"} {
		if slices.Contains(got, absent) {
			t.Errorf("the reader picked up %q, which is not a copied source directory: %v", absent, got)
		}
	}
	if len(got) != len(want) {
		t.Errorf("the reader found %d sources in a specimen with %d: %v", len(got), len(want), got)
	}
}

func dockerfileSources(t *testing.T) []string {
	t.Helper()
	return sourcesIn(t, dockerfilePath)
}

func sourcesIn(t *testing.T, path string) []string {
	t.Helper()
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading %s: %v — this guard fails rather than skipping", path, err)
	}
	var sources []string
	for _, match := range copyLine.FindAllStringSubmatch(string(body), -1) {
		fields := strings.Fields(match[1])
		if len(fields) < 2 {
			continue
		}
		// `COPY --from=build …` moves an artifact between stages and names no source directory in
		// this repo.
		if strings.HasPrefix(fields[0], "--from=") {
			continue
		}
		// The last field is the destination; `COPY go.mod go.sum ./` names two sources on one line.
		sources = append(sources, fields[:len(fields)-1]...)
	}
	return sources
}

// modulePackageDirs lists every directory holding a non-test Go file, relative to the module root.
func modulePackageDirs(t *testing.T) []string {
	t.Helper()
	root := "../.."
	seen := map[string]bool{}
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		relative, err := filepath.Rel(root, filepath.Dir(path))
		if err != nil {
			return err
		}
		seen[relative] = true
		return nil
	})
	if err != nil {
		t.Fatalf("walking the module: %v", err)
	}
	if len(seen) < 2 {
		t.Fatalf("found %d package directories, which cannot be right — the walker is not reading "+
			"the module", len(seen))
	}
	dirs := make([]string, 0, len(seen))
	for dir := range seen {
		dirs = append(dirs, dir)
	}
	slices.Sort(dirs)
	return dirs
}
