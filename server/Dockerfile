# PLACEHOLDER — R36 live-layer scaffolding, ticket #158.
# Deliberately boring and disposable: static Go binary on scratch, no dependencies,
# small image so the auto-start cold path stays short. Expect #158 to replace this.
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
ARG GIT_SHA=unknown
ENV CGO_ENABLED=0
RUN go build -trimpath -ldflags="-s -w" -o /out/server .

FROM scratch
ARG GIT_SHA=unknown
ENV GIT_SHA=${GIT_SHA}
ENV PORT=8080
COPY --from=build /out/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
