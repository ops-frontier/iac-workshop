FROM node:20-alpine

# Install git
RUN apk add --no-cache git

WORKDIR /app

# Copy package files
COPY docs-renew/package*.json ./

# Install dependencies
RUN npm install --production

# Copy application files
COPY docs-renew/server.js ./
COPY app/auth-common.js ./
COPY docs-renew/public/ ./public/

# Create docs directory
RUN mkdir -p /var/docs

# Expose port
EXPOSE 3001

# Start service
CMD ["node", "server.js"]
