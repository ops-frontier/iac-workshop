FROM node:20-alpine

# Install git and docker CLI
RUN apk add --no-cache git docker-cli

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
