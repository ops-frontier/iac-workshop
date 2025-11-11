FROM node:20-alpine

# Install git, docker CLI, and sudo
RUN apk add --no-cache git docker-cli sudo shadow

# Rename node user (UID 1000) to codespace
# Alpine uses deluser/adduser instead of usermod/groupmod
RUN deluser --remove-home node && \
    addgroup -g 1000 codespace && \
    adduser -D -u 1000 -G codespace -h /home/codespace -s /bin/sh codespace

WORKDIR /app

# Install dependencies
COPY package.json ./
RUN npm install --production

# Install @devcontainers/cli globally
RUN npm install -g @devcontainers/cli

# Copy application code
COPY . .

# Create data directory
RUN mkdir -p /app/data

# Expose port
EXPOSE 3000

# Start the application
CMD ["node", "server.js"]
