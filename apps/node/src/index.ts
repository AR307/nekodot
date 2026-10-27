import pino from 'pino';
const log = pino();
log.info(
  { service: 'nekodot-node', phase: 0 },
  'Node skeleton ready. Hermes spike is a separate explicit command.',
);
