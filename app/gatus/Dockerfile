FROM golang:1.26-alpine AS builder
WORKDIR /go/src/app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN apk add --no-cache ca-certificates
RUN CGO_ENABLED=0 GOOS=linux go build -o gatus .

FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=builder --chown=nonroot:nonroot /go/src/app/gatus /gatus
COPY --from=builder --chown=nonroot:nonroot /go/src/app/config.yaml /config/config.yaml
USER nonroot:nonroot
EXPOSE 8080
CMD ["/gatus"]