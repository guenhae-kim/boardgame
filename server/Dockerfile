FROM node:22-alpine
WORKDIR /app
COPY server/package*.json ./server/
RUN cd server && npm ci --omit=dev
COPY server ./server
COPY client/build/web ./client/build/web
ENV NODE_ENV=production
EXPOSE 8080
CMD ["node", "server/src/server.js"]
