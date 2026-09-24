const express = require('express');
const router = express.Router();
const licenseController = require('../controllers/licenseController');

// Client Machine DRM Endpoints
router.post('/client/activate', licenseController.clientActivate);
router.post('/client/heartbeat', licenseController.clientHeartbeat);
router.post('/client/trial-ping', licenseController.clientTrialPing);
router.post('/client/deactivate', licenseController.clientDeactivate);

// Public Endpoints (Accessible by Madarsa App & Seller App)
router.get('/plans', licenseController.getAllPlans);
router.get('/feature-catalog', licenseController.getFeatureCatalog);
router.get('/trial-config', licenseController.getTrialConfig);

// Seller / Admin Management Endpoints
router.get('/admin/licenses', licenseController.getAllLicenses);
router.post('/admin/create-key', licenseController.createLicense);
router.post('/admin/toggle-block', licenseController.toggleLicenseBlock);
router.post('/admin/licenses/:licenseId/permissions', licenseController.updateLicensePermissions);
router.post('/admin/unbind-device', licenseController.unbindDevice);
router.post('/admin/extend', licenseController.extendLicense);
router.delete('/admin/licenses/:id', licenseController.deleteLicense);
router.get('/admin/owner-pin', licenseController.getOwnerPin);
router.post('/admin/change-pin', licenseController.changeOwnerPin);

// Free Trial Users Telemetry & Kill-Switch
router.get('/admin/trial-users', licenseController.getAllTrialUsers);
router.post('/admin/toggle-trial-block', licenseController.toggleTrialBlock);
router.delete('/admin/trial-users/:hwid', licenseController.deleteTrialUser);

// Plan Templates CRUD Endpoints
router.post('/admin/plans', licenseController.createPlan);
router.put('/admin/plans/:id', licenseController.updatePlan);
router.delete('/admin/plans/:id', licenseController.deletePlan);

// Free Trial Config Endpoint
router.post('/admin/trial-config', licenseController.updateTrialConfig);

module.exports = router;
