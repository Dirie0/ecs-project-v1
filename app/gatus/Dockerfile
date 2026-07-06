FROM golang:1.26-alpine AS builder
WORKDIR /go/src/app
COPY go.mod go.sum ./
RUN go mod download

COPY . . 
RUN apk add --no-cache ca-certificates 
RUN CGO_ENABLED=0 GOOS=linux go build -o gatus . 


FROM scratch
COPY --from=builder /go/src/app/gatus gatus 
COPY --from=builder /go/src/app/config.yaml /config/config.yaml
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8080
CMD ["/gatus"]


