FROM golang:1.19-alpine AS builder

WORKDIR /app

# Copy and download dependencies using go mod
COPY go.mod go.sum ./
RUN go mod download

# Copy the source code into the container
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app .

# Use a small Alpine image for the final stage
FROM alpine:3.19

# Install certificates for HTTPS
RUN apk --no-cache add ca-certificates

WORKDIR /root/

# Copy the binary from the builder stage
COPY --from=builder /app/app .

# Expose application port
EXPOSE 8080

# Command to run the application
CMD ["./app"]
