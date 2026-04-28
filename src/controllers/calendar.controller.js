const db = require('../config/db');

// ========== EXISTING FUNCTIONS ==========

// Get available slots for a specific date
exports.getAvailableSlots = async (req, res) => {
    try {
        const { date } = req.params;
        const organizationId = req.query.orgId || 1;
        
        const result = await db.query(
            'SELECT * FROM get_available_slots($1, $2)',
            [organizationId, date]
        );
        
        res.json({
            success: true,
            date: date,
            slots: result.rows
        });
    } catch (error) {
        console.error('Error getting available slots:', error);
        res.status(500).json({ 
            success: false, 
            error: error.message 
        });
    }
};

// Create a new booking
exports.createBooking = async (req, res) => {
    const client = await db.getClient();
    
    try {
        await client.query('BEGIN');
        
        const {
            organization_id = 1,
            customer_name,
            customer_email,
            customer_phone,
            booking_date,
            start_time,
            end_time,
            service_id,
            staff_id,
            notes
        } = req.body;
        
        // Validate required fields
        if (!customer_name || !customer_email || !booking_date || !start_time || !end_time) {
            return res.status(400).json({ 
                success: false, 
                error: 'Missing required fields' 
            });
        }
        
        // Check if slot is available
        const availabilityCheck = await client.query(
            'SELECT is_slot_available($1, $2, $3, $4, $5)',
            [organization_id, booking_date, start_time, end_time, staff_id]
        );
        
        if (!availabilityCheck.rows[0].is_slot_available) {
            await client.query('ROLLBACK');
            return res.status(409).json({ 
                success: false, 
                error: 'This time slot is no longer available' 
            });
        }
        
        // Find or create customer
        let customerId;
        const existingCustomer = await client.query(
            `SELECT id FROM customers WHERE email = $1 AND organization_id = $2`,
            [customer_email, organization_id]
        );
        
        if (existingCustomer.rows.length > 0) {
            customerId = existingCustomer.rows[0].id;
        } else {
            const newCustomer = await client.query(
                `INSERT INTO customers (organization_id, name, email, phone) 
                 VALUES ($1, $2, $3, $4) RETURNING id`,
                [organization_id, customer_name, customer_email, customer_phone]
            );
            customerId = newCustomer.rows[0].id;
        }
        
        // Create booking
        const result = await client.query(
            `INSERT INTO bookings (
                organization_id, customer_id, service_id, staff_id,
                booking_date, start_time, end_time, 
                customer_name, customer_email, customer_phone, 
                notes, status
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'confirmed')
            RETURNING id, booking_date, start_time, end_time`,
            [
                organization_id, customerId, service_id || null, staff_id || null,
                booking_date, start_time, end_time,
                customer_name, customer_email, customer_phone,
                notes || null
            ]
        );
        
        await client.query('COMMIT');
        
        res.json({
            success: true,
            message: 'Booking confirmed successfully',
            booking: result.rows[0]
        });
        
    } catch (error) {
        await client.query('ROLLBACK');
        console.error('Error creating booking:', error);
        res.status(500).json({ 
            success: false, 
            error: error.message 
        });
    } finally {
        client.release();
    }
};

// Cancel a booking
exports.cancelBooking = async (req, res) => {
    try {
        const { id } = req.params;
        
        const result = await db.query(
            `UPDATE bookings SET status = 'cancelled', updated_at = CURRENT_TIMESTAMP 
             WHERE id = $1 AND status NOT IN ('cancelled', 'completed')
             RETURNING id, booking_date, start_time`,
            [id]
        );
        
        if (result.rows.length === 0) {
            return res.status(404).json({ 
                success: false, 
                error: 'Booking not found or already cancelled' 
            });
        }
        
        res.json({
            success: true,
            message: 'Booking cancelled successfully',
            booking: result.rows[0]
        });
    } catch (error) {
        console.error('Error cancelling booking:', error);
        res.status(500).json({ 
            success: false, 
            error: error.message 
        });
    }
};

// Get services
exports.getServices = async (req, res) => {
    try {
        const { orgId = 1 } = req.query;
        
        const result = await db.query(
            `SELECT id, name, description, duration_minutes, price, color
             FROM services WHERE organization_id = $1 AND is_active = true ORDER BY name`,
            [orgId]
        );
        
        res.json({ success: true, services: result.rows });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get staff
exports.getStaff = async (req, res) => {
    try {
        const { orgId = 1 } = req.query;
        
        const result = await db.query(
            `SELECT id, name, email, role, color
             FROM staff WHERE organization_id = $1 AND is_active = true ORDER BY name`,
            [orgId]
        );
        
        res.json({ success: true, staff: result.rows });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// ========== NEW FUNCTIONS ==========

// Get monthly calendar stats
exports.getMonthlyStats = async (req, res) => {
    try {
        const { year, month } = req.params;
        const organizationId = req.query.orgId || 1;
        
        const result = await db.query(
            'SELECT * FROM get_monthly_stats($1, $2, $3)',
            [organizationId, year, month]
        );
        
        res.json({ success: true, year, month, stats: result.rows });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get customer bookings by email
exports.getCustomerBookings = async (req, res) => {
    try {
        const { email } = req.params;
        const organizationId = req.query.orgId || 1;
        
        const result = await db.query(
            'SELECT * FROM get_customer_bookings($1, $2)',
            [email, organizationId]
        );
        
        res.json({ success: true, email, bookings: result.rows });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get organization info
exports.getOrganizationInfo = async (req, res) => {
    try {
        const organizationId = req.query.orgId || 1;
        
        const result = await db.query(
            'SELECT id, name, address, phone, email FROM organization WHERE id = $1',
            [organizationId]
        );
        
        if (result.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Organization not found' });
        }
        
        res.json({ success: true, organization: result.rows[0] });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get business hours
exports.getBusinessHours = async (req, res) => {
    try {
        const organizationId = req.query.orgId || 1;
        
        const result = await db.query('SELECT * FROM get_business_hours($1)', [organizationId]);
        
        res.json({ success: true, hours: result.rows });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};

// Get weekly view
exports.getWeeklyView = async (req, res) => {
    try {
        const { start_date } = req.params;
        const organizationId = req.query.orgId || 1;
        
        const endDate = new Date(start_date);
        endDate.setDate(endDate.getDate() + 7);
        const end_date = endDate.toISOString().split('T')[0];
        
        const result = await db.query(
            `SELECT booking_date, start_time, end_time, customer_name, status, id as booking_id
             FROM bookings
             WHERE organization_id = $1 AND booking_date BETWEEN $2 AND $3 AND status NOT IN ('cancelled')
             ORDER BY booking_date, start_time`,
            [organizationId, start_date, end_date]
        );
        
        const groupedByDate = {};
        result.rows.forEach(booking => {
            if (!groupedByDate[booking.booking_date]) {
                groupedByDate[booking.booking_date] = [];
            }
            groupedByDate[booking.booking_date].push(booking);
        });
        
        res.json({ success: true, start_date, end_date, bookings: groupedByDate });
    } catch (error) {
        res.status(500).json({ success: false, error: error.message });
    }
};