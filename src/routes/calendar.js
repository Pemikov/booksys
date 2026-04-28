const express = require('express');
const router = express.Router();
const calendarController = require('../controllers/calendar.controller');

// Existing routes
router.get('/availability/:date', calendarController.getAvailableSlots);
router.get('/weekly/:start_date', calendarController.getWeeklyView);
router.get('/business-hours', calendarController.getBusinessHours);
router.get('/services', calendarController.getServices);
router.get('/staff', calendarController.getStaff);
router.post('/bookings', calendarController.createBooking);
router.put('/bookings/:id/cancel', calendarController.cancelBooking);

// NEW routes for enhanced features
router.get('/monthly-stats/:year/:month', calendarController.getMonthlyStats);
router.get('/customer-bookings/:email', calendarController.getCustomerBookings);
router.get('/organization', calendarController.getOrganizationInfo);

module.exports = router;