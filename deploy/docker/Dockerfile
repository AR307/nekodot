FROM node:24.22.1-bookworm-slim
ENV NODE_ENV=production HOST=0.0.0.0 PORT=4329 DATA_DIR=/data DISTRIBUTION_DIR=/app/distribution
WORKDIR /app
COPY dist/relay/package.json ./package.json
RUN npm install --omit=dev --no-audit --no-fund && mkdir -p /data && chown node:node /data
COPY dist/relay/index.mjs ./index.mjs
COPY dist/distribution/ ./distribution/
USER node
EXPOSE 4329
CMD ["node", "index.mjs"]
