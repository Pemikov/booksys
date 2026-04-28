const pool = require('../db');
const { generateSlots } = require('./slotGenerator');

async function getDayAvailability(resourceId, date) {
  const day = new Date(date).getDay();

  const rules = await pool.query(
    'SELECT * FROM availability_rules WHERE resource_id=$1 AND day_of_week=$2',
    [resourceId, day]
  );

  if (rules.rows.length === 0) return [];

  const rule = rules.rows[0];
  const slots = generateSlots(date, rule);

  const bookings = await pool.query(
    'SELECT * FROM bookings WHERE resource_id=$1 AND DATE(start_time)=$2 AND status=$3',
    [resourceId, date, 'booked']
  );

  return slots.map(slot => {
    const isBooked = bookings.rows.some(b =>
      new Date(b.start_time) < slot.end &&
      new Date(b.end_time) > slot.start
    );

    return {
      ...slot,
      status: isBooked ? 'booked' : 'free'
    };
  });
}

module.exports = { getDayAvailability };