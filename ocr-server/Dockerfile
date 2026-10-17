FROM node:20-bookworm-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY . .

ENV NODE_ENV=production
ENV PORT=3001
ENV WHATSAPP_DATA_DIR=/data
ENV WHATSAPP_AUTH_DIR=/data/baileys_auth

RUN mkdir -p /data /data/baileys_auth

EXPOSE 3001
CMD ["node", "server.js"]
