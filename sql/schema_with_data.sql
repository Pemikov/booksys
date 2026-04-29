--
-- PostgreSQL database dump
--

\restrict 9IjgSpTdEm13E5RBcY4h2wdna1ugNVwq5t3oKKL8mucNqNrES7gKVRTBSa8OHZy

-- Dumped from database version 18.3 (Debian 18.3-1.pgdg13+1)
-- Dumped by pg_dump version 18.3 (Debian 18.3-1.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: get_available_slots(integer, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_available_slots(p_organization_id integer, p_booking_date date) RETURNS TABLE(slot_start time without time zone, slot_end time without time zone, is_available boolean, booking_id integer, staff_name character varying)
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: get_customer_bookings(character varying, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_customer_bookings(p_email character varying, p_organization_id integer DEFAULT 1) RETURNS TABLE(id integer, booking_date date, start_time time without time zone, end_time time without time zone, status character varying, service_name character varying, staff_name character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT 
        b.id,
        b.booking_date,
        b.start_time,
        b.end_time,
        b.status,
        COALESCE(s.name, 'No service')::VARCHAR as service_name,
        COALESCE(st.name, 'Any staff')::VARCHAR as staff_name
    FROM bookings b
    LEFT JOIN services s ON b.service_id = s.id
    LEFT JOIN staff st ON b.staff_id = st.id
    WHERE b.customer_email = p_email
        AND b.organization_id = p_organization_id
        AND b.status NOT IN ('cancelled')
    ORDER BY b.booking_date DESC, b.start_time ASC;
END;
$$;


--
-- Name: get_monthly_stats(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_monthly_stats(p_organization_id integer, p_year integer, p_month integer) RETURNS TABLE(day_date date, total_slots integer, booked_slots integer, free_slots integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH dates AS (
        SELECT generate_series(
            make_date(p_year, p_month, 1),
            make_date(p_year, p_month, 1) + INTERVAL '1 month - 1 day',
            INTERVAL '1 day'
        )::DATE as day_date
    ),
    business_slots AS (
        SELECT 
            d.day_date,
            COUNT(*)::INTEGER as slots_per_day
        FROM dates d
        JOIN business_hours bh ON bh.day_of_week = EXTRACT(DOW FROM d.day_date)
            AND bh.organization_id = p_organization_id
            AND bh.is_open = true
        CROSS JOIN LATERAL (
            SELECT generate_series(
                ('2000-01-01'::TIMESTAMP + bh.open_time),
                ('2000-01-01'::TIMESTAMP + bh.close_time) - (bh.slot_interval || ' minutes')::INTERVAL,
                (bh.slot_interval || ' minutes')::INTERVAL
            )::TIME as slot_start
        ) slots
        GROUP BY d.day_date
    ),
    daily_bookings AS (
        SELECT 
            booking_date,
            COUNT(*)::INTEGER as booked
        FROM bookings
        WHERE organization_id = p_organization_id
            AND EXTRACT(YEAR FROM booking_date) = p_year
            AND EXTRACT(MONTH FROM booking_date) = p_month
            AND status NOT IN ('cancelled')
        GROUP BY booking_date
    )
    SELECT 
        d.day_date,
        COALESCE(bs.slots_per_day, 0)::INTEGER as total_slots,
        COALESCE(db.booked, 0)::INTEGER as booked_slots,
        (COALESCE(bs.slots_per_day, 0) - COALESCE(db.booked, 0))::INTEGER as free_slots
    FROM dates d
    LEFT JOIN business_slots bs ON d.day_date = bs.day_date
    LEFT JOIN daily_bookings db ON d.day_date = db.booking_date
    ORDER BY d.day_date;
END;
$$;


--
-- Name: get_organizations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_organizations() RETURNS TABLE(id integer, name character varying, status character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT o.id, o.name, o.status
    FROM organization o
    WHERE o.status = 'active'
    ORDER BY o.name;
END;
$$;


--
-- Name: is_slot_available(integer, date, time without time zone, time without time zone, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_slot_available(p_organization_id integer, p_booking_date date, p_start_time time without time zone, p_end_time time without time zone, p_staff_id integer DEFAULT NULL::integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: update_business_hours(integer, integer, boolean, time without time zone, time without time zone, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_business_hours(p_organization_id integer, p_day_of_week integer, p_is_open boolean, p_open_time time without time zone, p_close_time time without time zone, p_slot_interval integer DEFAULT 30) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO business_hours (organization_id, day_of_week, is_open, open_time, close_time, slot_interval)
    VALUES (p_organization_id, p_day_of_week, p_is_open, p_open_time, p_close_time, p_slot_interval)
    ON CONFLICT (organization_id, day_of_week) 
    DO UPDATE SET 
        is_open = EXCLUDED.is_open,
        open_time = EXCLUDED.open_time,
        close_time = EXCLUDED.close_time,
        slot_interval = EXCLUDED.slot_interval;
    
    RETURN TRUE;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: admin_users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_users (
    id integer NOT NULL,
    organization_id integer,
    username character varying(100) NOT NULL,
    password_hash character varying(255) NOT NULL,
    email character varying(255),
    role character varying(50) DEFAULT 'admin'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    last_login timestamp without time zone
);


--
-- Name: admin_users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.admin_users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: admin_users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.admin_users_id_seq OWNED BY public.admin_users.id;


--
-- Name: blocked_times; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.blocked_times (
    id integer NOT NULL,
    organization_id integer NOT NULL,
    blocked_date date NOT NULL,
    start_time time without time zone,
    end_time time without time zone,
    reason character varying(255),
    is_all_day boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: blocked_times_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.blocked_times_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: blocked_times_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.blocked_times_id_seq OWNED BY public.blocked_times.id;


--
-- Name: booking_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.booking_history (
    id integer NOT NULL,
    booking_id integer NOT NULL,
    changed_by character varying(255),
    old_status character varying(50),
    new_status character varying(50),
    notes text,
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: booking_history_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.booking_history_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: booking_history_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.booking_history_id_seq OWNED BY public.booking_history.id;


--
-- Name: bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookings (
    id integer NOT NULL,
    organization_id integer NOT NULL,
    customer_id integer NOT NULL,
    service_id integer,
    staff_id integer,
    booking_date date NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    duration_minutes integer DEFAULT 30,
    customer_name character varying(255),
    customer_email character varying(255),
    customer_phone character varying(50),
    notes text,
    status character varying(50) DEFAULT 'confirmed'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT valid_status CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'confirmed'::character varying, 'cancelled'::character varying, 'completed'::character varying, 'no-show'::character varying])::text[]))),
    CONSTRAINT valid_time_range CHECK ((start_time < end_time))
);


--
-- Name: bookings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bookings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bookings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bookings_id_seq OWNED BY public.bookings.id;


--
-- Name: business_hours; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.business_hours (
    id integer NOT NULL,
    organization_id integer NOT NULL,
    day_of_week integer NOT NULL,
    is_open boolean DEFAULT true,
    open_time time without time zone,
    close_time time without time zone,
    slot_interval integer DEFAULT 30,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT business_hours_day_of_week_check CHECK (((day_of_week >= 0) AND (day_of_week <= 6))),
    CONSTRAINT valid_open_time CHECK ((open_time < close_time))
);


--
-- Name: business_hours_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.business_hours_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: business_hours_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.business_hours_id_seq OWNED BY public.business_hours.id;


--
-- Name: customers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customers (
    id integer NOT NULL,
    organization_id integer NOT NULL,
    name character varying(255) NOT NULL,
    email character varying(255),
    phone character varying(50),
    address text,
    postcode character varying(20),
    status character varying(50) DEFAULT 'active'::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: customers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.customers_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.customers_id_seq OWNED BY public.customers.id;


--
-- Name: organization; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    added date DEFAULT CURRENT_DATE,
    address text,
    phone character varying(50),
    email character varying(255),
    status character varying(50) DEFAULT 'active'::character varying
);


--
-- Name: organization_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.organization_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: organization_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.organization_id_seq OWNED BY public.organization.id;


--
-- Name: service_assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_assignments (
    staff_id integer NOT NULL,
    service_id integer NOT NULL,
    is_preferred boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.services (
    id integer NOT NULL,
    organization_id integer,
    name character varying(255) NOT NULL,
    description text,
    duration_minutes integer NOT NULL,
    buffer_minutes integer DEFAULT 0,
    price numeric(10,2),
    color character varying(7) DEFAULT '#2ecc71'::character varying,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: services_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.services_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: services_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.services_id_seq OWNED BY public.services.id;


--
-- Name: staff; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff (
    id integer NOT NULL,
    organization_id integer,
    name character varying(255) NOT NULL,
    email character varying(255),
    phone character varying(50),
    role character varying(100),
    color character varying(7) DEFAULT '#3498db'::character varying,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: staff_availability; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_availability (
    id integer NOT NULL,
    staff_id integer NOT NULL,
    booking_date date NOT NULL,
    is_available boolean DEFAULT true,
    custom_start_time time without time zone,
    custom_end_time time without time zone,
    reason character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT staff_availability_check CHECK ((custom_start_time < custom_end_time))
);


--
-- Name: staff_availability_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.staff_availability_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: staff_availability_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.staff_availability_id_seq OWNED BY public.staff_availability.id;


--
-- Name: staff_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.staff_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: staff_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.staff_id_seq OWNED BY public.staff.id;


--
-- Name: time_slots_template; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_slots_template (
    id integer NOT NULL,
    slot_start time without time zone NOT NULL,
    slot_end time without time zone NOT NULL,
    duration_minutes integer NOT NULL
);


--
-- Name: time_slots_template_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.time_slots_template_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: time_slots_template_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.time_slots_template_id_seq OWNED BY public.time_slots_template.id;


--
-- Name: admin_users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users ALTER COLUMN id SET DEFAULT nextval('public.admin_users_id_seq'::regclass);


--
-- Name: blocked_times id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_times ALTER COLUMN id SET DEFAULT nextval('public.blocked_times_id_seq'::regclass);


--
-- Name: booking_history id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_history ALTER COLUMN id SET DEFAULT nextval('public.booking_history_id_seq'::regclass);


--
-- Name: bookings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings ALTER COLUMN id SET DEFAULT nextval('public.bookings_id_seq'::regclass);


--
-- Name: business_hours id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_hours ALTER COLUMN id SET DEFAULT nextval('public.business_hours_id_seq'::regclass);


--
-- Name: customers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers ALTER COLUMN id SET DEFAULT nextval('public.customers_id_seq'::regclass);


--
-- Name: organization id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization ALTER COLUMN id SET DEFAULT nextval('public.organization_id_seq'::regclass);


--
-- Name: services id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services ALTER COLUMN id SET DEFAULT nextval('public.services_id_seq'::regclass);


--
-- Name: staff id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff ALTER COLUMN id SET DEFAULT nextval('public.staff_id_seq'::regclass);


--
-- Name: staff_availability id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_availability ALTER COLUMN id SET DEFAULT nextval('public.staff_availability_id_seq'::regclass);


--
-- Name: time_slots_template id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_slots_template ALTER COLUMN id SET DEFAULT nextval('public.time_slots_template_id_seq'::regclass);


--
-- Data for Name: admin_users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.admin_users (id, organization_id, username, password_hash, email, role, created_at, last_login) FROM stdin;
\.


--
-- Data for Name: blocked_times; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.blocked_times (id, organization_id, blocked_date, start_time, end_time, reason, is_all_day, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: booking_history; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.booking_history (id, booking_id, changed_by, old_status, new_status, notes, changed_at) FROM stdin;
\.


--
-- Data for Name: bookings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.bookings (id, organization_id, customer_id, service_id, staff_id, booking_date, start_time, end_time, duration_minutes, customer_name, customer_email, customer_phone, notes, status, created_at, updated_at) FROM stdin;
1	1	1	1	1	2026-04-30	10:00:00	10:30:00	30	John Customer	john@example.com	\N	\N	confirmed	2026-04-29 11:50:51.556221	2026-04-29 11:50:51.556221
\.


--
-- Data for Name: business_hours; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.business_hours (id, organization_id, day_of_week, is_open, open_time, close_time, slot_interval, created_at) FROM stdin;
1	1	1	t	09:00:00	17:00:00	30	2026-04-29 11:50:51.551506
2	1	2	t	09:00:00	17:00:00	30	2026-04-29 11:50:51.551506
3	1	3	t	09:00:00	17:00:00	30	2026-04-29 11:50:51.551506
4	1	4	t	09:00:00	17:00:00	30	2026-04-29 11:50:51.551506
5	1	5	t	09:00:00	17:00:00	30	2026-04-29 11:50:51.551506
6	1	6	f	\N	\N	30	2026-04-29 11:50:51.551506
7	1	0	f	\N	\N	30	2026-04-29 11:50:51.551506
\.


--
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customers (id, organization_id, name, email, phone, address, postcode, status, created_at) FROM stdin;
1	1	John Customer	john@example.com	555-0101	456 Oak Ave	\N	active	2026-04-29 11:50:51.544982
2	1	Jane Client	jane@example.com	555-0102	789 Pine Rd	\N	active	2026-04-29 11:50:51.544982
\.


--
-- Data for Name: organization; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.organization (id, name, added, address, phone, email, status) FROM stdin;
1	Sample Business	2026-04-29	123 Main St	555-0100	info@sample.com	active
\.


--
-- Data for Name: service_assignments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.service_assignments (staff_id, service_id, is_preferred, created_at) FROM stdin;
1	1	t	2026-04-29 11:50:51.553575
1	2	f	2026-04-29 11:50:51.553575
1	3	f	2026-04-29 11:50:51.553575
2	1	f	2026-04-29 11:50:51.553575
2	2	f	2026-04-29 11:50:51.553575
2	3	f	2026-04-29 11:50:51.553575
3	1	f	2026-04-29 11:50:51.553575
3	2	f	2026-04-29 11:50:51.553575
3	3	f	2026-04-29 11:50:51.553575
\.


--
-- Data for Name: services; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.services (id, organization_id, name, description, duration_minutes, buffer_minutes, price, color, is_active, created_at) FROM stdin;
1	1	Consultation	Initial 30-min consultation	30	0	50.00	#3498db	t	2026-04-29 11:50:51.549676
2	1	Standard Service	One hour standard service	60	0	100.00	#2ecc71	t	2026-04-29 11:50:51.549676
3	1	Premium Service	90-minute premium service	90	0	150.00	#e74c3c	t	2026-04-29 11:50:51.549676
\.


--
-- Data for Name: staff; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.staff (id, organization_id, name, email, phone, role, color, is_active, created_at, updated_at) FROM stdin;
1	1	Alice Manager	alice@sample.com	555-0201	Manager	#3498db	t	2026-04-29 11:50:51.547842	2026-04-29 11:50:51.547842
2	1	Bob Specialist	bob@sample.com	555-0202	Senior	#2ecc71	t	2026-04-29 11:50:51.547842	2026-04-29 11:50:51.547842
3	1	Carol Trainee	carol@sample.com	555-0203	Junior	#e74c3c	t	2026-04-29 11:50:51.547842	2026-04-29 11:50:51.547842
\.


--
-- Data for Name: staff_availability; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.staff_availability (id, staff_id, booking_date, is_available, custom_start_time, custom_end_time, reason, created_at) FROM stdin;
\.


--
-- Data for Name: time_slots_template; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.time_slots_template (id, slot_start, slot_end, duration_minutes) FROM stdin;
1	00:00:00	00:30:00	30
2	00:30:00	01:00:00	30
3	01:00:00	01:30:00	30
4	01:30:00	02:00:00	30
5	02:00:00	02:30:00	30
6	02:30:00	03:00:00	30
7	03:00:00	03:30:00	30
8	03:30:00	04:00:00	30
9	04:00:00	04:30:00	30
10	04:30:00	05:00:00	30
11	05:00:00	05:30:00	30
12	05:30:00	06:00:00	30
13	06:00:00	06:30:00	30
14	06:30:00	07:00:00	30
15	07:00:00	07:30:00	30
16	07:30:00	08:00:00	30
17	08:00:00	08:30:00	30
18	08:30:00	09:00:00	30
19	09:00:00	09:30:00	30
20	09:30:00	10:00:00	30
21	10:00:00	10:30:00	30
22	10:30:00	11:00:00	30
23	11:00:00	11:30:00	30
24	11:30:00	12:00:00	30
25	12:00:00	12:30:00	30
26	12:30:00	13:00:00	30
27	13:00:00	13:30:00	30
28	13:30:00	14:00:00	30
29	14:00:00	14:30:00	30
30	14:30:00	15:00:00	30
31	15:00:00	15:30:00	30
32	15:30:00	16:00:00	30
33	16:00:00	16:30:00	30
34	16:30:00	17:00:00	30
35	17:00:00	17:30:00	30
36	17:30:00	18:00:00	30
37	18:00:00	18:30:00	30
38	18:30:00	19:00:00	30
39	19:00:00	19:30:00	30
40	19:30:00	20:00:00	30
41	20:00:00	20:30:00	30
42	20:30:00	21:00:00	30
43	21:00:00	21:30:00	30
44	21:30:00	22:00:00	30
45	22:00:00	22:30:00	30
46	22:30:00	23:00:00	30
47	23:00:00	23:30:00	30
48	23:30:00	00:00:00	30
49	00:00:00	00:30:00	30
50	01:00:00	01:30:00	30
51	02:00:00	02:30:00	30
52	03:00:00	03:30:00	30
53	04:00:00	04:30:00	30
54	05:00:00	05:30:00	30
55	06:00:00	06:30:00	30
56	07:00:00	07:30:00	30
57	08:00:00	08:30:00	30
58	09:00:00	09:30:00	30
59	10:00:00	10:30:00	30
60	11:00:00	11:30:00	30
61	12:00:00	12:30:00	30
62	13:00:00	13:30:00	30
63	14:00:00	14:30:00	30
64	15:00:00	15:30:00	30
65	16:00:00	16:30:00	30
66	17:00:00	17:30:00	30
67	18:00:00	18:30:00	30
68	19:00:00	19:30:00	30
69	20:00:00	20:30:00	30
70	21:00:00	21:30:00	30
71	22:00:00	22:30:00	30
72	23:00:00	23:30:00	30
\.


--
-- Name: admin_users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.admin_users_id_seq', 1, false);


--
-- Name: blocked_times_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.blocked_times_id_seq', 1, false);


--
-- Name: booking_history_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.booking_history_id_seq', 1, false);


--
-- Name: bookings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.bookings_id_seq', 7, true);


--
-- Name: business_hours_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.business_hours_id_seq', 11, true);


--
-- Name: customers_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.customers_id_seq', 2, true);


--
-- Name: organization_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.organization_id_seq', 1, true);


--
-- Name: services_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.services_id_seq', 1, false);


--
-- Name: staff_availability_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.staff_availability_id_seq', 1, false);


--
-- Name: staff_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.staff_id_seq', 1, false);


--
-- Name: time_slots_template_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.time_slots_template_id_seq', 72, true);


--
-- Name: admin_users admin_users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_pkey PRIMARY KEY (id);


--
-- Name: admin_users admin_users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_username_key UNIQUE (username);


--
-- Name: blocked_times blocked_times_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_times
    ADD CONSTRAINT blocked_times_pkey PRIMARY KEY (id);


--
-- Name: booking_history booking_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_history
    ADD CONSTRAINT booking_history_pkey PRIMARY KEY (id);


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (id);


--
-- Name: business_hours business_hours_organization_id_day_of_week_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_hours
    ADD CONSTRAINT business_hours_organization_id_day_of_week_key UNIQUE (organization_id, day_of_week);


--
-- Name: business_hours business_hours_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_hours
    ADD CONSTRAINT business_hours_pkey PRIMARY KEY (id);


--
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (id);


--
-- Name: organization organization_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization
    ADD CONSTRAINT organization_pkey PRIMARY KEY (id);


--
-- Name: service_assignments service_assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_assignments
    ADD CONSTRAINT service_assignments_pkey PRIMARY KEY (staff_id, service_id);


--
-- Name: services services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_pkey PRIMARY KEY (id);


--
-- Name: staff_availability staff_availability_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_availability
    ADD CONSTRAINT staff_availability_pkey PRIMARY KEY (id);


--
-- Name: staff staff_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_email_key UNIQUE (email);


--
-- Name: staff staff_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_pkey PRIMARY KEY (id);


--
-- Name: time_slots_template time_slots_template_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_slots_template
    ADD CONSTRAINT time_slots_template_pkey PRIMARY KEY (id);


--
-- Name: business_hours unique_org_day; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_hours
    ADD CONSTRAINT unique_org_day UNIQUE (organization_id, day_of_week);


--
-- Name: idx_blocked_times_org_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_blocked_times_org_date ON public.blocked_times USING btree (organization_id, blocked_date);


--
-- Name: idx_bookings_customer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_customer ON public.bookings USING btree (customer_id);


--
-- Name: idx_bookings_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_date ON public.bookings USING btree (booking_date);


--
-- Name: idx_bookings_org_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_org_date ON public.bookings USING btree (organization_id, booking_date);


--
-- Name: idx_bookings_staff_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_staff_date ON public.bookings USING btree (staff_id, booking_date);


--
-- Name: idx_bookings_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_status ON public.bookings USING btree (status);


--
-- Name: idx_business_hours_organization; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_business_hours_organization ON public.business_hours USING btree (organization_id);


--
-- Name: idx_customers_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_email ON public.customers USING btree (email);


--
-- Name: idx_customers_organization; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customers_organization ON public.customers USING btree (organization_id);


--
-- Name: idx_services_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_services_active ON public.services USING btree (is_active);


--
-- Name: idx_services_organization; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_services_organization ON public.services USING btree (organization_id);


--
-- Name: idx_staff_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staff_active ON public.staff USING btree (is_active);


--
-- Name: idx_staff_availability_staff_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staff_availability_staff_date ON public.staff_availability USING btree (staff_id, booking_date);


--
-- Name: idx_staff_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staff_email ON public.staff USING btree (email);


--
-- Name: idx_staff_organization; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_staff_organization ON public.staff USING btree (organization_id);


--
-- Name: unique_booking_per_org; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_booking_per_org ON public.bookings USING btree (organization_id, booking_date, start_time) WHERE ((staff_id IS NULL) AND ((status)::text <> ALL ((ARRAY['cancelled'::character varying, 'completed'::character varying])::text[])));


--
-- Name: unique_booking_per_staff; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_booking_per_staff ON public.bookings USING btree (staff_id, booking_date, start_time) WHERE ((status)::text <> ALL ((ARRAY['cancelled'::character varying, 'completed'::character varying])::text[]));


--
-- Name: blocked_times update_blocked_times_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_blocked_times_updated_at BEFORE UPDATE ON public.blocked_times FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: bookings update_bookings_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_bookings_updated_at BEFORE UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: staff update_staff_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER update_staff_updated_at BEFORE UPDATE ON public.staff FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();


--
-- Name: admin_users admin_users_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_users
    ADD CONSTRAINT admin_users_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: blocked_times blocked_times_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.blocked_times
    ADD CONSTRAINT blocked_times_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: booking_history booking_history_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.booking_history
    ADD CONSTRAINT booking_history_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.services(id) ON DELETE SET NULL;


--
-- Name: bookings bookings_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE SET NULL;


--
-- Name: business_hours business_hours_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.business_hours
    ADD CONSTRAINT business_hours_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: customers customers_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: service_assignments service_assignments_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_assignments
    ADD CONSTRAINT service_assignments_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.services(id) ON DELETE CASCADE;


--
-- Name: service_assignments service_assignments_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_assignments
    ADD CONSTRAINT service_assignments_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: services services_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- Name: staff_availability staff_availability_staff_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_availability
    ADD CONSTRAINT staff_availability_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.staff(id) ON DELETE CASCADE;


--
-- Name: staff staff_organization_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff
    ADD CONSTRAINT staff_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict 9IjgSpTdEm13E5RBcY4h2wdna1ugNVwq5t3oKKL8mucNqNrES7gKVRTBSa8OHZy

