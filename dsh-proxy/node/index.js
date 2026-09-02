'use strict';
// Environment-based entry point for the DSH reverse proxy.
// Configure via environment variables or .env file.
const { startProxy } = require('./proxy-core');

const LISTEN_PORT = Number(process.env.PROXY_PORT) || 3080;
const DSH_PORT = Number(process.env.DSH_PORT) || 3079;

startProxy({
  listenPort: LISTEN_PORT,
  dshPort: DSH_PORT,
  username: process.env.PROXY_USERNAME || '',
  password: process.env.PROXY_PASSWORD || '',
});
