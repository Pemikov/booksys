CREATE TABLE resources (
  id SERIAL PRIMARY KEY,
  name TEXT
);

CREATE TABLE availability_rules (
  id SERIAL PRIMARY KEY,
  resource_id INT,
  day_of_week INT,
  start_time TIME,
  end_time TIME,
  slot_duration INT
);

CREATE TABLE bookings (
  id SERIAL PRIMARY KEY,
  resource_id INT,
  start_time TIMESTAMP,
  end_time TIMESTAMP,
  status TEXT DEFAULT 'booked'
);

CREATE TABLE blocked_slots (
  id SERIAL PRIMARY KEY,
  resource_id INT,
  start_time TIMESTAMP,
  end_time TIMESTAMP
);

-- prevent double booking
CREATE UNIQUE INDEX unique_booking
ON bookings(resource_id, start_time, end_time)
WHERE status = 'booked';