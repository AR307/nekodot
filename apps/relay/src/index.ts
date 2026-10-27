import Fastify from 'fastify';
const app = Fastify({ logger: true });
app.get('/health', () => ({ service: 'nekodot-relay', phase: 0, status: 'ok' }));
await app.listen({ host: '127.0.0.1', port: 4319 });
