# Base image
FROM ubuntu:22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    python3 \
    python3-pip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI
RUN pip3 install awscli

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Make script executable
RUN chmod +x manage_cloudant.sh

# Default command
CMD ["./manage_cloudant.sh", "backup"]
