const db = require('../config/db');

// Get organization settings
exports.getSettings = async (req, res) => {
    try {
        const orgId = req.organizationId;
        
        const orgResult = await db.query(
            `SELECT id, name, slug, logo_url, primary_color, timezone, 
                    max_advance_booking_days, min_notice_hours, address, phone, email, currency
             FROM organization WHERE id = $1`,
            [orgId]
        );
        
        let hoursResult = { rows: [] };
        try {
            hoursResult = await db.query(
                `SELECT id, day_of_week, is_open, open_time, close_time, slot_interval
                 FROM business_hours WHERE organization_id = $1 ORDER BY day_of_week`,
                [orgId]
            );
        } catch (err) {
            console.log('Error fetching business hours:', err.message);
        }
        
        let notifResult = { rows: [] };
        try {
            notifResult = await db.query(`SELECT * FROM notification_settings WHERE organization_id = $1`, [orgId]);
        } catch (err) {}
        
        res.json({
            success: true,
            organization: orgResult.rows[0] || {},
            business_hours: hoursResult.rows,
            notifications: notifResult.rows[0] || {}
        });
    } catch (error) {
        console.error('getSettings error:', error);
        res.status(500).json({ success: false, error: error.message });
    }
};

// Admin-only availability with customer details
exports.getAdminAvailability = async (req, res) => {
    try {
        const { date } = req.params;
        const orgId = req.organizationId;

        const result = await db.query(
            `SELECT 
                ts.slot_start,
                ts.slot_end,
                CASE WHEN b.id IS NULL THEN true ELSE false END as is_available,
                b.id as booking_id,
                s.name as staff_name,
                c.name as customer_name,
                c.email as customer_email
             FROM time_slots_template ts
             CROSS JOIN business_hours bh
             LEFT JOIN bookings b ON 
                 b.booking_date = $2
                 AND b.start_time = ts.slot_start
                 AND b.organization_id = $1
                 AND b.status NOT IN ('cancelled', 'completed')
             LEFT JOIN staff s ON b.staff_id = s.id
             LEFT JOIN customers c ON b.customer_id = c.id
             WHERE bh.organization_id = $1
                 AND bh.day_of_week = EXTRACT(DOW FROM $2::DATE)
                 AND bh.is_open = true
                 AND ts.slot_start >= bh.open_time
                 AND ts.slot_end <= bh.close_time
             ORDER BY ts.slot_start`,
            [orgId, date]
        );

        res.json({ success: true, slots: result.rows });
    } catch (error) {
        console.error('Error fetching admin availability:', error);
        res.status(500).json({ success: false, error: error.message });
    }
};

// Update business hours
exports.updateBusinessHours = async (req, res) => {
    try {
        const orgId = req.organizationId;
        const { hours } = req.body;
        
        for (const hour of hours) {
            await db.query(
                `INSERT INTO business_hours (organization_id, day_of_week, is_open, open_time, close_time, slot_interval)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 ON CONFLICT (organization_id, day_of_week)
                 DO UPDATE SET is_open = EXCLUDED.is_open, open_time = EXCLUDED.open_time, 
                               close_time = EXCLUDED.close_time, slot_interval = EXCLUDED.slot_interval`,
                [orgId, hour.day_of_week, hour.is_open, hour.open_time, hour.close_time, hour.slot_interval || 30]
            );
        }
        res.json({ success: true, message: 'Business hours updated' });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Update organization
exports.updateOrganization = async (req, res) => {
    try {
        const orgId = req.organizationId;
        const { name, logo_url, primary_color, timezone, max_advance_booking_days, min_notice_hours, address, phone, email, currency } = req.body;
        
        await db.query(
            `UPDATE organization 
             SET name = COALESCE($1, name),
                 logo_url = COALESCE($2, logo_url),
                 primary_color = COALESCE($3, primary_color),
                 timezone = COALESCE($4, timezone),
                 max_advance_booking_days = COALESCE($5, max_advance_booking_days),
                 min_notice_hours = COALESCE($6, min_notice_hours),
                 address = COALESCE($7, address),
                 phone = COALESCE($8, phone),
                 email = COALESCE($9, email),
                 currency = COALESCE($10, currency)
             WHERE id = $11`,
            [name, logo_url, primary_color, timezone, max_advance_booking_days, min_notice_hours, address, phone, email, currency, orgId]
        );
        
        res.json({ success: true, message: 'Organization updated' });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get all customers
exports.getCustomers = async (req, res) => {
    try {
        const orgId = req.organizationId;
        const { search, sort_by = 'created_at', sort_order = 'DESC' } = req.query;
        
        let query = `
            SELECT c.id, c.name, c.email, c.phone, c.created_at,
                   COUNT(b.id) as total_bookings,
                   MAX(b.booking_date) as last_booking_date
            FROM customers c
            LEFT JOIN bookings b ON c.id = b.customer_id AND b.organization_id = $1
            WHERE c.organization_id = $1
        `;
        const params = [orgId];
        
        if (search) {
            query += ` AND (c.name ILIKE $2 OR c.email ILIKE $2 OR c.phone ILIKE $2)`;
            params.push(`%${search}%`);
        }
        
        query += ` GROUP BY c.id ORDER BY ${sort_by} ${sort_order}`;
        
        const result = await db.query(query, params);
        res.json({ success: true, customers: result.rows });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get all bookings (admin)
exports.getBookings = async (req, res) => {
    try {
        const orgId = req.organizationId;
        const { start_date, end_date, status, customer_id } = req.query;
        
        let query = `
            SELECT b.id, b.booking_date, b.start_time, b.end_time, b.status, b.created_at,
                   c.name as customer_name, c.email as customer_email, c.phone as customer_phone,
                   s.name as service_name, st.name as staff_name
            FROM bookings b
            LEFT JOIN customers c ON b.customer_id = c.id
            LEFT JOIN services s ON b.service_id = s.id
            LEFT JOIN staff st ON b.staff_id = st.id
            WHERE b.organization_id = $1
        `;
        const params = [orgId];
        let paramIndex = 2;
        
        if (start_date) {
            query += ` AND b.booking_date >= $${paramIndex++}`;
            params.push(start_date);
        }
        if (end_date) {
            query += ` AND b.booking_date <= $${paramIndex++}`;
            params.push(end_date);
        }
        if (status) {
            query += ` AND b.status = $${paramIndex++}`;
            params.push(status);
        }
        if (customer_id) {
            query += ` AND b.customer_id = $${paramIndex++}`;
            params.push(customer_id);
        }
        
        query += ` ORDER BY b.booking_date DESC, b.start_time ASC`;
        
        const result = await db.query(query, params);
        res.json({ success: true, bookings: result.rows });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Update booking status
exports.updateBookingStatus = async (req, res) => {
    try {
        const { id } = req.params;
        const { status } = req.body;
        
        const result = await db.query(
            `UPDATE bookings SET status = $1, updated_at = CURRENT_TIMESTAMP 
             WHERE id = $2 AND organization_id = $3
             RETURNING *`,
            [status, id, req.organizationId]
        );
        
        if (result.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Booking not found' });
        }
        
        res.json({ success: true, booking: result.rows[0] });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get all services
exports.getServices = async (req, res) => {
    try {
        const orgId = req.organizationId;
        const result = await db.query(
            `SELECT * FROM services WHERE organization_id = $1 ORDER BY name`,
            [orgId]
        );
        res.json({ success: true, services: result.rows });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get single service by ID
exports.getServiceById = async (req, res) => {
    try {
        const { id } = req.params;
        const orgId = req.organizationId;

        const result = await db.query(
            `SELECT * FROM services WHERE id = $1 AND organization_id = $2`,
            [id, orgId]
        );

        if (result.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Service not found' });
        }

        res.json({ success: true, service: result.rows[0] });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Create/update service (handles both insert and update)
exports.saveService = async (req, res) => {
    try {
        const orgId = req.organizationId;
        const { id, name, description, duration_minutes, buffer_minutes, price, is_active } = req.body;

        let result;
        // If id exists and is a number, perform UPDATE
        if (id && !isNaN(parseInt(id))) {
            result = await db.query(
                `UPDATE services 
                 SET name = $1, description = $2, duration_minutes = $3, 
                     buffer_minutes = $4, price = $5, is_active = $6
                 WHERE id = $7 AND organization_id = $8
                 RETURNING *`,
                [name, description, duration_minutes, buffer_minutes, price, is_active, id, orgId]
            );
            if (result.rows.length === 0) {
                return res.status(404).json({ success: false, error: 'Service not found or not owned by organization' });
            }
        } else {
            // Insert new service
            result = await db.query(
                `INSERT INTO services (organization_id, name, description, duration_minutes, buffer_minutes, price, is_active)
                 VALUES ($1, $2, $3, $4, $5, $6, $7)
                 RETURNING *`,
                [orgId, name, description, duration_minutes, buffer_minutes, price, is_active]
            );
        }
        res.json({ success: true, service: result.rows[0] });
    } catch (error) {
        console.error('Error saving service:', error);
        res.status(500).json({ success: false, error: error.message });
    }
};

// Delete service
exports.deleteService = async (req, res) => {
    try {
        const { id } = req.params;
        await db.query(
            `DELETE FROM services WHERE id = $1 AND organization_id = $2`,
            [id, req.organizationId]
        );
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get all staff
exports.getStaff = async (req, res) => {
    try {
        const orgId = req.organizationId;
        const result = await db.query(
            `SELECT * FROM staff WHERE organization_id = $1 ORDER BY name`,
            [orgId]
        );
        res.json({ success: true, staff: result.rows });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Save staff (insert/update)
exports.saveStaff = async (req, res) => {
    try {
        const orgId = req.organizationId;
        const { id, name, email, phone, role, color, is_active } = req.body;
        
        let result;
        if (id && !isNaN(parseInt(id))) {
            result = await db.query(
                `UPDATE staff SET name = $1, email = $2, phone = $3, role = $4, color = $5, is_active = $6, updated_at = CURRENT_TIMESTAMP
                 WHERE id = $7 AND organization_id = $8 RETURNING *`,
                [name, email, phone, role, color, is_active, id, orgId]
            );
        } else {
            result = await db.query(
                `INSERT INTO staff (organization_id, name, email, phone, role, color, is_active)
                 VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
                [orgId, name, email, phone, role, color, is_active]
            );
        }
        res.json({ success: true, staff: result.rows[0] });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Delete staff
exports.deleteStaff = async (req, res) => {
    try {
        const { id } = req.params;
        await db.query(
            `DELETE FROM staff WHERE id = $1 AND organization_id = $2`,
            [id, req.organizationId]
        );
        res.json({ success: true });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Save notification settings
exports.saveNotificationSettings = async (req, res) => {
    try {
        const orgId = req.organizationId;
        const { email_enabled, sms_enabled, webhook_enabled, webhook_url, email_from } = req.body;
        
        await db.query(
            `INSERT INTO notification_settings (organization_id, email_enabled, sms_enabled, webhook_enabled, webhook_url, email_from)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (organization_id) DO UPDATE SET
                email_enabled = EXCLUDED.email_enabled,
                sms_enabled = EXCLUDED.sms_enabled,
                webhook_enabled = EXCLUDED.webhook_enabled,
                webhook_url = EXCLUDED.webhook_url,
                email_from = EXCLUDED.email_from,
                updated_at = CURRENT_TIMESTAMP`,
            [orgId, email_enabled, sms_enabled, webhook_enabled, webhook_url, email_from]
        );
        
        res.json({ success: true, message: 'Notification settings saved' });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get shareable link
exports.getShareableLink = async (req, res) => {
    try {
        const orgId = req.organizationId;
        const result = await db.query(
            `SELECT slug FROM organization WHERE id = $1`,
            [orgId]
        );
        const slug = result.rows[0]?.slug;
        const link = `${req.protocol}://${req.get('host')}/book/${slug}`;
        res.json({ success: true, link });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get booking page by slug (public)
exports.getBookingPageBySlug = async (req, res) => {
    try {
        const { slug } = req.params;
        const result = await db.query(
            `SELECT id, name, slug, logo_url, primary_color, timezone, address, phone, email, currency
             FROM organization WHERE slug = $1 AND status = 'active'`,
            [slug]
        );
        if (result.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Organization not found' });
        }
        res.json({ success: true, organization: result.rows[0] });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};