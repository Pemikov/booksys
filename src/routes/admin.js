const express = require('express');
const router = express.Router();
const adminController = require('../controllers/admin.controller');
const { isAuthenticated } = require('../middleware/auth');

// All admin routes require authentication
router.use(isAuthenticated);

// Availability (admin version)
router.get('/availability/:date', adminController.getAdminAvailability);

// Audit Logs
router.get('/audit-logs', adminController.getAuditLogs);

// Customers
router.get('/customers', adminController.getCustomers);
router.get('/customers/:id', adminController.getCustomerById);
router.post('/customers', adminController.saveCustomer);
router.delete('/customers/:id', adminController.deleteCustomer);

// Settings
router.get('/settings', adminController.getSettings);
router.put('/settings/business-hours', adminController.updateBusinessHours);
router.put('/settings/organization', adminController.updateOrganization);
router.get('/settings/shareable-link', adminController.getShareableLink);

// Bookings
router.get('/bookings', adminController.getBookings);
router.put('/bookings/:id/status', adminController.updateBookingStatus);
router.put('/bookings/:id/no-show', adminController.markAsNoShow);
router.post('/bookings/:bookingId/remind', adminController.sendReminder);
router.put('/bookings/:id/reschedule', adminController.rescheduleBooking);
router.put('/bookings/:id/no-show', adminController.markAsNoShow);
router.post('/bookings/recurring', adminController.createRecurringBookings);

// Services
router.get('/services', adminController.getServices);
router.get('/services/:id', adminController.getServiceById);   // <-- ADD THIS
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