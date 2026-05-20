# Dockerfile for Cloudant Backup Script - Optimized for IBM Code Engine
# Base image with Node.js for @cloudant/couchbackup
FROM node:18-alpine

# Install required dependencies
RUN apk add --no-cache \
    bash \
    curl \
    python3 \
    py3-pip \
    && pip3 install --no-cache-dir --break-system-packages awscli

# Install @cloudant/couchbackup globally
RUN npm install -g @cloudant/couchbackup

# Create backup directory and set permissions
# Use existing node user (uid/gid 1000) instead of creating new user
RUN mkdir -p /app/backup && \
    chown -R node:node /app

# Set working directory
WORKDIR /app

# Copy the backup script
COPY manage_cloudant.sh /app/manage_cloudant.sh

# Make script executable
RUN chmod +x /app/manage_cloudant.sh && \
    chown node:node /app/manage_cloudant.sh

# Switch to non-root user (use existing node user)
USER node

# Set default command (can be overridden in Code Engine job definition)
CMD ["/app/manage_cloudant.sh", "backup"]

# Made with Bob
