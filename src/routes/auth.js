const express = require('express');
const router = express.Router();
const authController = require('../controllers/auth.controller');
const { isAuthenticated } = require('../middleware/auth');

router.post('/admin/login', authController.adminLogin);
router.post('/admin/logout', isAuthenticated, authController.adminLogout);
router.get('/admin/me', isAuthenticated, authController.getCurrentAdmin);

module.exports = router;