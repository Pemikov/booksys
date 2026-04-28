const express = require('express');
const router = express.Router();
const { getDayAvailability } = require('../services/availabilityService');
const pool = require('../db');

router.get('/day', async (req, res) => {
  const { resourceId, date } = req.query;

  const data = await getDayAvailability(resourceId, date);
  res.json(data);
});

router.get('/month', async (req, res) => {
  const { resourceId } = req.query;

  const result = await pool.query(`
    SELECT DATE(start_time) as day, COUNT(*) as booked
    FROM bookings
    WHERE resource_id=$1 AND status='booked'
    GROUP BY day
  `, [resourceId]);

  res.json(result.rows);
});

module.exports = router;