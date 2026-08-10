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

COPY main.go ./
COPY internal ./internal

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
