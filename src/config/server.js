// Load .env FIRST, before anything else
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });

console.log("ENV CHECK:", {
  DB_HOST: process.env.DB_HOST,
  DB_PORT: process.env.DB_PORT,
  DB_NAME: process.env.DB_NAME,
  PORT: process.env.PORT
});

const express = require('express');
const cors = require('cors');
const calendarRoutes = require('../routes/calendar');
const db = require('./db');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../../public')));

// Routes
app.use('/api/calendar', calendarRoutes);

// Health check
app.get('/api/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Simple frontend route
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, '../../public/index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on http://localhost:${PORT}`);
    console.log(`📅 Calendar API: http://localhost:${PORT}/api/calendar`);
    console.log(`✅ Health check: http://localhost:${PORT}/api/health`);
});