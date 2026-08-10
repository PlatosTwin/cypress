# The sync service (#158, RULINGS R72).
#
# Static binary on scratch, as the placeholder was — the reasoning survives the rewrite: a small
# image keeps the auto-start cold path short, and the machine stops when idle, so that path is
# walked several times a day rather than at deploy time only.
#
# Go 1.25 rather than 1.23: `coreos/go-oidc/v3` requires it. That is the only reason.
FROM golang:1.25-alpine AS build
WORKDIR /src

# Dependencies first, so a change to the service does not re-download the module graph.
COPY go.mod go.sum ./
RUN go mod download

# **Every directory the module compiles, and nothing else.**
#
# This is an allowlist, and an allowlist rots: `migrations/` was added after this file was written
# and the first real image build died on
# `no required module provides package github.com/PlatosTwin/cypress/server/migrations`. The SQL is
# compiled in by `//go:embed`, so a missing directory is a *build* failure rather than a runtime
# one — which is the good version of this mistake, but only because the embed happens to exist.
#
# `TestDockerfileCopiesEveryPackage` in `internal/store` is the guard: it reads this file and fails
# when a package directory is not copied. Add a package, add a COPY.
#
# `testdata/` is deliberately absent: it is read only by tests, which do not run in this image.
COPY main.go ./
COPY internal ./internal
COPY migrations ./migrations

ARG GIT_SHA=unknown
ENV CGO_ENABLED=0
# `-trimpath` keeps the build directory out of the binary; `-s -w` drops the symbol and DWARF
# tables, which is most of the size on a Go binary.
RUN go build -trimpath -ldflags="-s -w" -o /out/server .

FROM scratch
ARG GIT_SHA=unknown
ENV GIT_SHA=${GIT_SHA}
ENV PORT=8080

# The TLS roots, which `scratch` does not have. Without them every outbound call this service makes
# — Apple's JWKS, Apple's token and revocation endpoints — fails with an unhelpful
# `x509: certificate signed by unknown authority`, and it fails at *sign-in*, not at boot.
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

COPY --from=build /out/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
