-- ============================================
-- COMPLETE BOOKING SYSTEM SCHEMA (FIXED)
-- Run this entire script in DBeaver
-- ============================================

-- Drop existing tables if they exist (order matters due to foreign keys)
DROP TABLE IF EXISTS booking_history CASCADE;
DROP TABLE IF EXISTS service_assignments CASCADE;
DROP TABLE IF EXISTS staff_availability CASCADE;
DROP TABLE IF EXISTS blocked_times CASCADE;
DROP TABLE IF EXISTS business_hours CASCADE;
DROP TABLE IF EXISTS bookings CASCADE;
DROP TABLE IF EXISTS services CASCADE;
DROP TABLE IF EXISTS staff CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS organization CASCADE;
DROP TABLE IF EXISTS time_slots_template CASCADE;

-- Drop existing functions
DROP FUNCTION IF EXISTS generate_time_slots(TIME, TIME, INTEGER);
DROP FUNCTION IF EXISTS generate_time_slots_simple(TIME, TIME, INTEGER);
DROP FUNCTION IF EXISTS is_slot_available(INTEGER, DATE, TIME, TIME, INTEGER);
DROP FUNCTION IF EXISTS update_updated_at_column();
DROP FUNCTION IF EXISTS get_available_slots(INTEGER, DATE);

-- ============================================
-- CORE TABLES
-- ============================================

-- Organization table
CREATE TABLE organization (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    added DATE DEFAULT CURRENT_DATE,
    address TEXT,
    phone VARCHAR(50),
    email VARCHAR(255),
    status VARCHAR(50) DEFAULT 'active'
);

-- Customers table
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(50),
    address TEXT,
    postcode VARCHAR(20),
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Staff table
CREATE TABLE staff (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER REFERENCES organization(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(50),
    role VARCHAR(100),
    color VARCHAR(7) DEFAULT '#3498db',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Services table
CREATE TABLE services (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER REFERENCES organization(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    duration_minutes INTEGER NOT NULL,
    buffer_minutes INTEGER DEFAULT 0,
    price DECIMAL(10, 2),
    color VARCHAR(7) DEFAULT '#2ecc71',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Bookings table
CREATE TABLE bookings (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    customer_id INTEGER NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
    service_id INTEGER REFERENCES services(id) ON DELETE SET NULL,
    staff_id INTEGER REFERENCES staff(id) ON DELETE SET NULL,
    booking_date DATE NOT NULL,
    start_time TIME WITHOUT TIME ZONE NOT NULL,
    end_time TIME WITHOUT TIME ZONE NOT NULL,
    duration_minutes INTEGER DEFAULT 30,
    customer_name VARCHAR(255),
    customer_email VARCHAR(255),
    customer_phone VARCHAR(50),
    notes TEXT,
    status VARCHAR(50) DEFAULT 'confirmed',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT valid_status CHECK (status IN ('pending', 'confirmed', 'cancelled', 'completed', 'no-show')),
    CONSTRAINT valid_time_range CHECK (start_time < end_time)
);

-- ============================================
-- CALENDAR & SCHEDULING TABLES
-- ============================================

-- Business hours (when customers can book)
CREATE TABLE business_hours (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
    is_open BOOLEAN DEFAULT true,
    open_time TIME WITHOUT TIME ZONE,
    close_time TIME WITHOUT TIME ZONE,
    slot_interval INTEGER DEFAULT 30,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(organization_id, day_of_week),
    CONSTRAINT valid_open_time CHECK (open_time < close_time)
);

-- Staff availability overrides (vacation, sick days)
CREATE TABLE staff_availability (
    id SERIAL PRIMARY KEY,
    staff_id INTEGER NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
    booking_date DATE NOT NULL,
    is_available BOOLEAN DEFAULT true,
    custom_start_time TIME WITHOUT TIME ZONE,
    custom_end_time TIME WITHOUT TIME ZONE,
    reason VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CHECK (custom_start_time < custom_end_time)
);

-- Service assignments (which staff can do which services)
CREATE TABLE service_assignments (
    staff_id INTEGER NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
    service_id INTEGER NOT NULL REFERENCES services(id) ON DELETE CASCADE,
    is_preferred BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    PRIMARY KEY (staff_id, service_id)
);

-- Blocked times (holidays, company events, maintenance)
CREATE TABLE blocked_times (
    id SERIAL PRIMARY KEY,
    organization_id INTEGER NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    blocked_date DATE NOT NULL,
    start_time TIME WITHOUT TIME ZONE,
    end_time TIME WITHOUT TIME ZONE,
    reason VARCHAR(255),
    is_all_day BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Booking history (audit log)
CREATE TABLE booking_history (
    id SERIAL PRIMARY KEY,
    booking_id INTEGER NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
    changed_by VARCHAR(255),
    old_status VARCHAR(50),
    new_status VARCHAR(50),
    notes TEXT,
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Time slots template (for fast calendar queries)
CREATE TABLE time_slots_template (
    id SERIAL PRIMARY KEY,
    slot_start TIME WITHOUT TIME ZONE NOT NULL,
    slot_end TIME WITHOUT TIME ZONE NOT NULL,
    duration_minutes INTEGER NOT NULL
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

-- Bookings indexes
CREATE INDEX idx_bookings_org_date ON bookings(organization_id, booking_date);
CREATE INDEX idx_bookings_staff_date ON bookings(staff_id, booking_date);
CREATE INDEX idx_bookings_customer ON bookings(customer_id);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_date ON bookings(booking_date);

-- Staff indexes
CREATE INDEX idx_staff_organization ON staff(organization_id);
CREATE INDEX idx_staff_email ON staff(email);
CREATE INDEX idx_staff_active ON staff(is_active);

-- Services indexes
CREATE INDEX idx_services_organization ON services(organization_id);
CREATE INDEX idx_services_active ON services(is_active);

-- Customers indexes
CREATE INDEX idx_customers_organization ON customers(organization_id);
CREATE INDEX idx_customers_email ON customers(email);

-- Business hours indexes
CREATE INDEX idx_business_hours_organization ON business_hours(organization_id);

-- Staff availability indexes
CREATE INDEX idx_staff_availability_staff_date ON staff_availability(staff_id, booking_date);

-- Blocked times indexes
CREATE INDEX idx_blocked_times_org_date ON blocked_times(organization_id, blocked_date);

-- ============================================
-- PREVENT DOUBLE BOOKING
-- ============================================

-- Prevent overlapping bookings for same staff
CREATE UNIQUE INDEX unique_booking_per_staff 
ON bookings(staff_id, booking_date, start_time)
WHERE status NOT IN ('cancelled', 'completed');

-- Prevent overlapping bookings for same org (if no staff assigned)
CREATE UNIQUE INDEX unique_booking_per_org 
ON bookings(organization_id, booking_date, start_time)
WHERE staff_id IS NULL AND status NOT IN ('cancelled', 'completed');

-- ============================================
-- FIXED FUNCTIONS (Working in PostgreSQL)
-- ============================================

-- Function to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to check if a time slot is available
CREATE OR REPLACE FUNCTION is_slot_available(
    p_organization_id INTEGER,
    p_booking_date DATE,
    p_start_time TIME,
    p_end_time TIME,
    p_staff_id INTEGER DEFAULT NULL
)
RETURNS BOOLEAN AS $$
DECLARE
    v_count INTEGER;
BEGIN
    -- Check for overlapping bookings
    SELECT COUNT(*) INTO v_count
    FROM bookings
    WHERE organization_id = p_organization_id
        AND booking_date = p_booking_date
        AND status NOT IN ('cancelled', 'completed')
        AND (staff_id = p_staff_id OR (p_staff_id IS NULL AND staff_id IS NULL))
        AND (start_time, end_time) OVERLAPS (p_start_time, p_end_time);
    
    RETURN v_count = 0;
END;
$$ LANGUAGE plpgsql;

-- Function to get available slots for a day
CREATE OR REPLACE FUNCTION get_available_slots(
    p_organization_id INTEGER,
    p_booking_date DATE
)
RETURNS TABLE(
    slot_start TIME,
    slot_end TIME,
    is_available BOOLEAN,
    booking_id INTEGER,
    staff_name VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        t.slot_start,
        t.slot_end,
        CASE WHEN b.id IS NULL THEN true ELSE false END as is_available,
        b.id as booking_id,
        s.name as staff_name
    FROM time_slots_template t
    CROSS JOIN business_hours bh
    LEFT JOIN bookings b ON 
        b.booking_date = p_booking_date
        AND b.start_time = t.slot_start
        AND b.organization_id = p_organization_id
        AND b.status NOT IN ('cancelled', 'completed')
    LEFT JOIN staff s ON b.staff_id = s.id
    WHERE bh.organization_id = p_organization_id
        AND bh.day_of_week = EXTRACT(DOW FROM p_booking_date)
        AND bh.is_open = true
        AND t.slot_start >= bh.open_time
        AND t.slot_end <= bh.close_time
    ORDER BY t.slot_start;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-update updated_at on bookings
DROP TRIGGER IF EXISTS update_bookings_updated_at ON bookings;
CREATE TRIGGER update_bookings_updated_at
    BEFORE UPDATE ON bookings
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Auto-update updated_at on staff
DROP TRIGGER IF EXISTS update_staff_updated_at ON staff;
CREATE TRIGGER update_staff_updated_at
    BEFORE UPDATE ON staff
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Auto-update updated_at on blocked_times
DROP TRIGGER IF EXISTS update_blocked_times_updated_at ON blocked_times;
CREATE TRIGGER update_blocked_times_updated_at
    BEFORE UPDATE ON blocked_times
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- POPULATE TIME SLOTS TEMPLATE
-- ============================================

-- Insert 30-minute time slots from 00:00 to 23:30
INSERT INTO time_slots_template (slot_start, slot_end, duration_minutes)
SELECT 
    slot_start,
    slot_start + INTERVAL '30 minutes' as slot_end,
    30
FROM (
    SELECT generate_series('00:00:00'::TIME, '23:30:00'::TIME, '30 minutes'::INTERVAL) as slot_start
) slots
ON CONFLICT DO NOTHING;

-- ============================================
-- SAMPLE DATA
-- ============================================

-- Insert sample organization
INSERT INTO organization (name, address, phone, email) 
VALUES ('Sample Business', '123 Main St', '555-0100', 'info@sample.com')
ON CONFLICT DO NOTHING;

-- Insert sample customers
INSERT INTO customers (organization_id, name, email, phone, address) 
VALUES 
    (1, 'John Customer', 'john@example.com', '555-0101', '456 Oak Ave'),
    (1, 'Jane Client', 'jane@example.com', '555-0102', '789 Pine Rd')
ON CONFLICT DO NOTHING;

-- Insert sample staff
INSERT INTO staff (organization_id, name, email, phone, role, color) 
VALUES 
    (1, 'Alice Manager', 'alice@sample.com', '555-0201', 'Manager', '#3498db'),
    (1, 'Bob Specialist', 'bob@sample.com', '555-0202', 'Senior', '#2ecc71'),
    (1, 'Carol Trainee', 'carol@sample.com', '555-0203', 'Junior', '#e74c3c')
ON CONFLICT (email) DO NOTHING;

-- Insert sample services
INSERT INTO services (organization_id, name, description, duration_minutes, price, color) 
VALUES 
    (1, 'Consultation', 'Initial 30-min consultation', 30, 50.00, '#3498db'),
    (1, 'Standard Service', 'One hour standard service', 60, 100.00, '#2ecc71'),
    (1, 'Premium Service', '90-minute premium service', 90, 150.00, '#e74c3c')
ON CONFLICT DO NOTHING;

-- Insert sample business hours (Mon-Fri 9AM-5PM)
INSERT INTO business_hours (organization_id, day_of_week, is_open, open_time, close_time, slot_interval)
VALUES 
    (1, 1, true, '09:00:00', '17:00:00', 30), -- Monday
    (1, 2, true, '09:00:00', '17:00:00', 30), -- Tuesday
    (1, 3, true, '09:00:00', '17:00:00', 30), -- Wednesday
    (1, 4, true, '09:00:00', '17:00:00', 30), -- Thursday
    (1, 5, true, '09:00:00', '17:00:00', 30), -- Friday
    (1, 6, false, NULL, NULL, 30),            -- Saturday
    (1, 0, false, NULL, NULL, 30)             -- Sunday
ON CONFLICT (organization_id, day_of_week) DO NOTHING;

-- Insert sample service assignments
INSERT INTO service_assignments (staff_id, service_id, is_preferred)
SELECT s.id, sv.id, 
    CASE WHEN s.role = 'Manager' AND sv.name = 'Consultation' THEN true ELSE false END
FROM staff s, services sv
WHERE s.organization_id = 1 AND sv.organization_id = 1
ON CONFLICT (staff_id, service_id) DO NOTHING;

-- Insert a sample booking for tomorrow at 10:00 AM
INSERT INTO bookings (
    organization_id, 
    customer_id, 
    service_id, 
    staff_id, 
    booking_date, 
    start_time, 
    end_time, 
    duration_minutes,
    customer_name,
    customer_email,
    status
)
SELECT 
    1,
    c.id,
    sv.id,
    s.id,
    CURRENT_DATE + 1,
    '10:00:00',
    '10:30:00',
    30,
    c.name,
    c.email,
    'confirmed'
FROM customers c, services sv, staff s
WHERE c.name = 'John Customer' 
    AND sv.name = 'Consultation'
    AND s.name = 'Alice Manager'
LIMIT 1
ON CONFLICT DO NOTHING;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Show all tables created
SELECT 
    table_name, 
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = t.table_name) as column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
    AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- Test the availability function
SELECT is_slot_available(1, CURRENT_DATE + 1, '10:00:00', '10:30:00', NULL) as is_10am_available;

-- Show available slots for tomorrow using the function
SELECT * FROM get_available_slots(1, CURRENT_DATE + 1);

-- Sample query for daily calendar view
SELECT 
    t.slot_start,
    t.slot_end,
    CASE WHEN b.id IS NULL THEN 'available' ELSE 'booked' END as status,
    b.customer_name,
    b.id as booking_id
FROM time_slots_template t
CROSS JOIN business_hours bh
LEFT JOIN bookings b ON 
    b.booking_date = CURRENT_DATE + 1
    AND b.start_time = t.slot_start
    AND b.organization_id = 1
WHERE bh.organization_id = 1
    AND bh.day_of_week = EXTRACT(DOW FROM CURRENT_DATE + 1)
    AND bh.is_open = true
    AND t.slot_start >= bh.open_time
    AND t.slot_end <= bh.close_time
ORDER BY t.slot_start;

-- ============================================
-- SUCCESS MESSAGE
-- ============================================
DO $$
BEGIN
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'DATABASE SETUP COMPLETE!';
    RAISE NOTICE '==========================================';
    RAISE NOTICE 'All tables and functions created successfully!';
    RAISE NOTICE '';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '1. Test calendar query above';
    RAISE NOTICE '2. Run: SELECT * FROM get_available_slots(1, CURRENT_DATE + 1);';
    RAISE NOTICE '3. Start your Node.js backend';
    RAISE NOTICE '==========================================';
END $$;