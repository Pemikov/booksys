// src/app.js - Alternative entry point (optional)
require('dotenv').config();
const server = require('./config/server');

// This file just exists to maintain compatibility
// The actual server is started from config/server.js

console.log('Starting from app.js...');
console.log('Use "npm run dev" or "npm start" to run the server');