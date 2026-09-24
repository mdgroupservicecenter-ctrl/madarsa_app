const express = require('express');
const router = express.Router();
const dashboardController = require('../controllers/dashboardController');
const { authenticateToken } = require('../middleware/auth');

// We use authenticateToken since dashboard is internal
router.get('/summary', authenticateToken, dashboardController.getDashboardSummary);

module.exports = router;
