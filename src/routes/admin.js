const express = require('express');
const router = express.Router();
const adminController = require('../controllers/admin.controller');
const { isAuthenticated } = require('../middleware/auth');

// All admin routes require authentication
router.use(isAuthenticated);

// Settings
router.get('/settings', adminController.getSettings);
router.put('/settings/business-hours', adminController.updateBusinessHours);
router.put('/settings/organization', adminController.updateOrganization);
router.get('/settings/shareable-link', adminController.getShareableLink);

// Customers
router.get('/customers', adminController.getCustomers);

// Bookings
router.get('/bookings', adminController.getBookings);
router.put('/bookings/:id/status', adminController.updateBookingStatus);

// Services
router.get('/services', adminController.getServices);
router.post('/services', adminController.saveService);
router.delete('/services/:id', adminController.deleteService);

// Staff
router.get('/staff', adminController.getStaff);
router.post('/staff', adminController.saveStaff);
router.delete('/staff/:id', adminController.deleteStaff);

// Notifications
router.put('/notifications', adminController.saveNotificationSettings);

// Public (for customer page - no auth needed)
router.get('/booking/:slug', adminController.getBookingPageBySlug);

module.exports = router;