const pool = require("../config/db");

const SLOT_MINUTES = 30;

// generate slots dynamically
function generateSlots(start, end) {
  const slots = [];
  let current = new Date(start);

  const endTime = new Date(end);

  while (current < endTime) {
    const next = new Date(current.getTime() + SLOT_MINUTES * 60000);

    slots.push({
      start: new Date(current),
      end: new Date(next),
      status: "free"
    });

    current = next;
  }

  return slots;
}

// PUBLIC availability (no details)
exports.getPublicSlots = async (clinicId) => {
  const result = await pool.query(
    "SELECT * FROM bookings WHERE clinic_id=$1",
    [clinicId]
  );

  return result.rows;
};

// BOOK slot
exports.bookSlot = async (data) => {
  const { clinic_id, customer_id, start_time, end_time } = data;

  const result = await pool.query(
    `INSERT INTO bookings (clinic_id, customer_id, start_time, end_time, status)
     VALUES ($1,$2,$3,$4,'booked')
     RETURNING *`,
    [clinic_id, customer_id, start_time, end_time]
  );

  return result.rows[0];
};

// CANCEL with rule check placeholder
exports.cancelSlot = async (data) => {
  const { booking_id } = data;

  const result = await pool.query(
    `UPDATE bookings SET status='cancelled' WHERE id=$1 RETURNING *`,
    [booking_id]
  );

  return result.rows[0];
};