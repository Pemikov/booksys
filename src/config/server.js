// Load .env FIRST
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });

const express = require('express');
const cors = require('cors');
const db = require('./db');

// Import routes
const calendarRoutes = require('../routes/calendar');
const adminRoutes = require('../routes/admin');
const authRoutes = require('../routes/auth');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../../public')));

// API Routes
app.use('/api/calendar', calendarRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/auth', authRoutes);

// Health check
app.get('/api/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Customer booking page by slug
app.get('/book/:slug', (req, res) => {
    res.sendFile(path.join(__dirname, '../../public/customer-booking.html'));
});

// Admin pages
app.get('/admin', (req, res) => {
    res.sendFile(path.join(__dirname, '../../public/admin-login.html'));
});

app.get('/admin/dashboard', (req, res) => {
    res.sendFile(path.join(__dirname, '../../public/admin-dashboard.html'));
});

// Default route (for testing - shows customer view for org ID 1)
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, '../../public/customer-booking.html'));
});

app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on http://localhost:${PORT}`);
    console.log(`📅 Customer booking: http://localhost:${PORT}/book/demo-clinic`);
    console.log(`🔐 Admin login: http://localhost:${PORT}/admin`);
    console.log(`✅ Health check: http://localhost:${PORT}/api/health`);
});