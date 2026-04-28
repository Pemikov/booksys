const express = require('express');
const router = express.Router();
const pool = require('../db');

router.post('/create', async (req, res) => {
  const { resourceId, start, end } = req.body;

  try {
    const result = await pool.query(
      'INSERT INTO bookings(resource_id, start_time, end_time) VALUES($1,$2,$3) RETURNING *',
      [resourceId, start, end]
    );

    res.json(result.rows[0]);
  } catch (err) {
    res.status(400).json({ error: 'Slot already booked' });
  }
});

router.post('/cancel', async (req, res) => {
  const { id } = req.body;

  await pool.query(
    'UPDATE bookings SET status=$1 WHERE id=$2',
    ['cancelled', id]
  );

  res.json({ success: true });
});

module.exports = router;