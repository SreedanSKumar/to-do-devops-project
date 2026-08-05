FROM node:20-alpine AS base
WORKDIR /app

COPY package*.json ./
RUN npm install --omit=dev

COPY . .

# Run as non-root user for better security posture in EKS
RUN adduser -D -u 1001 appuser
USER 1001

ENV PORT=5000
EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:5000/health || exit 1

CMD ["node", "server.js"]
