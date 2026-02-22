# Use the official Golang image as a base image
FROM golang:1.16 AS builder

# Set the ARG for TigrisFS version
ARG TIGRISFS_VERSION=0.3.1

# Set the working directory
WORKDIR /app

# Copy go.mod and go.sum files
COPY go.mod go.sum ./

# Download the dependencies
RUN go mod download

# Copy the source code
COPY . .

# Build the application
RUN go build -o myapp .

# Final stage
FROM alpine:latest

# Install curl
RUN apk --no-cache add curl

# Install opencode with improved fallback logic
RUN curl -sSL https://github.com/opencode/install-script.sh | bash || (echo 'Primary installation failed, fallback to alternative method.' && curl -sSL https://alternative-install-script.sh | bash)

# Create a mount directory for S3
RUN mkdir -p /mnt/s3

# Enhanced S3 mounting with local fallback
CMD if [ -d /mnt/s3 ]; then echo 'Mounting S3...' && /mount-s3-script.sh; else echo 'Fallback to local storage'; fi

# Copy the built application from builder stage
COPY --from=builder /app/myapp /bin/myapp

# Start the application
ENTRYPOINT ["/bin/myapp"]