const express = require('express');
const router = express.Router();
const purchasesController = require('../controllers/purchasesController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

// All routes require authentication
router.use(authenticateToken);

// ─── TRANSACTIONS (PURCHASES & SELLS) ─────────────────────────────────
router.get('/', requirePermission('purchases', 'view'), purchasesController.getTransactions);
router.post('/', requirePermission('purchases', 'create'), purchasesController.createTransaction);
router.put('/:id', requirePermission('purchases', 'edit'), purchasesController.updateTransaction);
router.delete('/:id', requirePermission('purchases', 'delete'), purchasesController.deleteTransaction);

// ─── UNIT OPTIONS MANAGEMENT ──────────────────────────────────────────
router.get('/units', requirePermission('purchases', 'view'), purchasesController.getUnits);
router.post('/units', requirePermission('purchases', 'create'), purchasesController.createUnit);
router.delete('/units/:id', requirePermission('purchases', 'delete'), purchasesController.deleteUnit);

// ─── CATEGORY OPTIONS MANAGEMENT ──────────────────────────────────────
router.get('/categories', requirePermission('purchases', 'view'), purchasesController.getCategories);
router.post('/categories', requirePermission('purchases', 'create'), purchasesController.createCategory);
router.delete('/categories/:id', requirePermission('purchases', 'delete'), purchasesController.deleteCategory);

// ─── GENERAL / ASSET STOCK MANAGEMENT ─────────────────────────────────
router.get('/general-stock', requirePermission('purchases', 'view'), purchasesController.getGeneralStock);
router.post('/general-stock/issue', requirePermission('purchases', 'create'), purchasesController.issueGeneralStock);
router.put('/general-stock/:id', requirePermission('purchases', 'edit'), purchasesController.updateGeneralStockItem);
router.delete('/general-stock/:id', requirePermission('purchases', 'delete'), purchasesController.deleteGeneralStockItem);

module.exports = router;
