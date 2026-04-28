const express = require('express');
const router = express.Router();
const calendarController = require('../controllers/calendar.controller');

// Public calendar routes
router.get('/availability/:date', calendarController.getAvailableSlots);
router.get('/weekly/:start_date', calendarController.getWeeklyCalendar);
router.get('/business-hours', calendarController.getBusinessHours);
router.post('/bookings', calendarController.createBooking);
router.put('/bookings/:id/cancel', calendarController.cancelBooking);

module.exports = router;