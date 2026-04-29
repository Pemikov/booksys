const db = require('../config/db');

const isAuthenticated = async (req, res, next) => {
    const token = req.headers.authorization;
    if (!token) return res.status(401).json({ success: false, error: 'No token' });

    try {
        const result = await db.query(
            `SELECT a.*, o.id as organization_id 
             FROM organization_admins a
             JOIN organization o ON a.organization_id = o.id
             WHERE a.session_token = $1`,
            [token]
        );
        if (result.rows.length === 0) return res.status(401).json({ success: false, error: 'Invalid token' });

        req.adminId = result.rows[0].id;
        req.organizationId = result.rows[0].organization_id;
        req.userRole = result.rows[0].role;
        next();
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

module.exports = { isAuthenticated };