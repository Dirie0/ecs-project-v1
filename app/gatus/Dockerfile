FROM golang:1.26-alpine AS builder

WORKDIR /app

COPY . . 

RUN CGO_ENABLED=0 GOOS=linux go build -o gatus . 


FROM scratch
COPY --from=builder /app/gatus gatus 
COPY --from=builder /app/config.yaml /config/config.yaml
EXPOSE 8080
CMD ["/gatus"]




