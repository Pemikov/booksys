const db = require('../config/db');
const crypto = require('crypto');

// Hash password (use bcrypt in production)
function hashPassword(password) {
    return crypto.createHash('sha256').update(password).digest('hex');
}

// Admin login
exports.adminLogin = async (req, res) => {
    try {
        const { email, password } = req.body;
        const passwordHash = hashPassword(password);
        
        const result = await db.query(
            `SELECT a.*, o.id as org_id, o.name as org_name, o.slug 
             FROM organization_admins a
             JOIN organization o ON a.organization_id = o.id
             WHERE a.email = $1 AND a.password_hash = $2`,
            [email, passwordHash]
        );
        
        if (result.rows.length === 0) {
            return res.status(401).json({ success: false, error: 'Invalid credentials' });
        }
        
        const admin = result.rows[0];
        const sessionToken = crypto.randomBytes(64).toString('hex');
        
        // Update last login and session token
        await db.query(
            `UPDATE organization_admins SET last_login = CURRENT_TIMESTAMP, session_token = $1 WHERE id = $2`,
            [sessionToken, admin.id]
        );
        
        res.json({
            success: true,
            token: sessionToken,
            admin: {
                id: admin.id,
                email: admin.email,
                name: admin.name,
                organization_id: admin.organization_id,
                organization_name: admin.org_name,
                organization_slug: admin.slug
            }
        });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Admin logout
exports.adminLogout = async (req, res) => {
    try {
        await db.query(
            `UPDATE organization_admins SET session_token = NULL WHERE id = $1`,
            [req.adminId]
        );
        res.json({ success: true, message: 'Logged out' });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get current admin info
exports.getCurrentAdmin = async (req, res) => {
    try {
        const result = await db.query(
            `SELECT a.id, a.email, a.name, a.role, o.id as organization_id, o.name as organization_name, o.slug
             FROM organization_admins a
             JOIN organization o ON a.organization_id = o.id
             WHERE a.id = $1`,
            [req.adminId]
        );
        
        res.json({ success: true, admin: result.rows[0] });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};