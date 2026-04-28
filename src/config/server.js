const express = require('express');
const cors = require('cors');
const path = require('path');
require('dotenv').config();

// Adjust paths - go up two levels from src/config to root
const calendarRoutes = require('../../routes/calendar.routes');
const db = require('./db'); // db.js should also be in src/config

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../../public'))); // Go up to root/public

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

app.listen(PORT, () => {
    console.log(`🚀 Server running on http://localhost:${PORT}`);
    console.log(`📅 Calendar API: http://localhost:${PORT}/api/calendar`);
});