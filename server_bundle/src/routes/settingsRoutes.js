const express = require('express');
const router = express.Router();
const settingsController = require('../controllers/settingsController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

// Protect all settings routes
router.use(authenticateToken);
router.use(requirePermission('settings', 'view'));

router.get('/website', settingsController.getWebsiteSettings);
router.get('/general', settingsController.getGeneralSettings);

// Editing settings requires 'edit' permission
router.put('/website', requirePermission('settings', 'edit'), settingsController.updateWebsiteSettings);
router.put('/general', requirePermission('settings', 'edit'), settingsController.updateGeneralSettings);

// Madarsa Shifts
router.get('/shifts', settingsController.getShifts);
router.post('/shifts', requirePermission('settings', 'edit'), settingsController.createShift);
router.put('/shifts/:id', requirePermission('settings', 'edit'), settingsController.updateShift);
router.delete('/shifts/:id', requirePermission('settings', 'edit'), settingsController.deleteShift);

module.exports = router;
