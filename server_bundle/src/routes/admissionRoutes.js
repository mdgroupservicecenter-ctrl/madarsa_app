const express = require('express');
const router = express.Router();
const { submitAdmission, getAdmissions } = require('../controllers/admissionController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

// Public route for website submission
router.post('/', submitAdmission);

// Protected routes for admin management
router.get('/', authenticateToken, requirePermission('students', 'view'), getAdmissions);

module.exports = router;
