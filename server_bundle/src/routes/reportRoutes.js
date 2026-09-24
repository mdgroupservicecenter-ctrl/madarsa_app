const express = require('express');
const router = express.Router();
const reportController = require('../controllers/reportController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

// All report routes are protected and require 'view' permission for 'reports' module
router.use(authenticateToken);
router.use(requirePermission('reports', 'view'));

router.get('/attendance', reportController.getAttendanceSummary);
router.get('/fees', reportController.getFeeSummary);
router.get('/students', reportController.getStudentStats);

module.exports = router;
