const express = require('express');
const router = express.Router();
const feesController = require('../controllers/feesController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

// All routes require token authentication
router.use(authenticateToken);

// Fees Module routes
router.get('/students', requirePermission('fees', 'view'), feesController.getStudentFeeSummaries);
router.get('/student/:studentId', requirePermission('fees', 'view'), feesController.getStudentPayments);
router.post('/pay', requirePermission('fees', 'create'), feesController.payFee);
router.delete('/payment/:id', requirePermission('fees', 'delete'), feesController.deleteFeePayment);

// Fee Types CRUD
router.get('/fee-types', requirePermission('fees', 'view'), feesController.getFeeTypes);
router.post('/fee-types', requirePermission('fees', 'create'), feesController.createFeeType);
router.put('/fee-types/:id', requirePermission('fees', 'edit'), feesController.updateFeeType);
router.delete('/fee-types/:id', requirePermission('fees', 'delete'), feesController.deleteFeeType);

// Donations routes
router.get('/donations', requirePermission('fees', 'view'), feesController.getDonations);
router.post('/donations', requirePermission('fees', 'create'), feesController.createDonation);
router.delete('/donations/:id', requirePermission('fees', 'delete'), feesController.deleteDonation);

// Donation Types CRUD
router.get('/donation-types', requirePermission('fees', 'view'), feesController.getDonationTypes);
router.post('/donation-types', requirePermission('fees', 'create'), feesController.createDonationType);
router.put('/donation-types/:id', requirePermission('fees', 'edit'), feesController.updateDonationType);
router.delete('/donation-types/:id', requirePermission('fees', 'delete'), feesController.deleteDonationType);

// SMS overdue check
router.post('/check-overdue', requirePermission('fees', 'view'), feesController.checkOverdueFees);

module.exports = router;
