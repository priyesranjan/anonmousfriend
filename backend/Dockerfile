FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY . .

# Expose port (default 5000)
EXPOSE 5000

# Start command
CMD ["npm", "start"]
