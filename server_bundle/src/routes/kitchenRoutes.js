const express = require('express');
const router = express.Router();
const kitchenController = require('../controllers/kitchenController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

// All routes require authentication
router.use(authenticateToken);

// ─── DAILY FOOD MENU ───────────────────────────────────────────────
router.get('/menu', requirePermission('kitchen', 'view'), kitchenController.getMenu);
router.put('/menu', requirePermission('kitchen', 'edit'), kitchenController.updateMenuItem);
router.delete('/menu/:id', requirePermission('kitchen', 'delete'), kitchenController.deleteMenuItem);
router.post('/menu/issue-today', requirePermission('kitchen', 'create'), kitchenController.issueTodayMenuRation);

// ─── RATION STOCK ──────────────────────────────────────────────────
router.get('/stock', requirePermission('kitchen', 'view'), kitchenController.getStock);
router.post('/stock', requirePermission('kitchen', 'create'), kitchenController.createStockItem);
router.put('/stock/:id', requirePermission('kitchen', 'edit'), kitchenController.updateStockItem);
router.delete('/stock/:id', requirePermission('kitchen', 'delete'), kitchenController.deleteStockItem);

// ─── STOCK TRANSACTIONS ────────────────────────────────────────────
router.get('/stock/transactions', requirePermission('kitchen', 'view'), kitchenController.getStockTransactions);
router.post('/stock/transactions', requirePermission('kitchen', 'create'), kitchenController.recordStockTransaction);
router.post('/stock/issue-meal', requirePermission('kitchen', 'create'), kitchenController.issueMealRation);

// ─── EXPENSES ──────────────────────────────────────────────────────
router.get('/expenses', requirePermission('kitchen', 'view'), kitchenController.getExpenses);
router.post('/expenses', requirePermission('kitchen', 'create'), kitchenController.createExpense);
router.delete('/expenses/:id', requirePermission('kitchen', 'delete'), kitchenController.deleteExpense);

// ─── MEAL PLANNING ─────────────────────────────────────────────────
router.get('/meal-plans', requirePermission('kitchen', 'view'), kitchenController.getMealPlans);
router.post('/meal-plans', requirePermission('kitchen', 'create'), kitchenController.createMealPlan);
router.put('/meal-plans/:id', requirePermission('kitchen', 'edit'), kitchenController.updateMealPlan);
router.delete('/meal-plans/:id', requirePermission('kitchen', 'delete'), kitchenController.deleteMealPlan);

module.exports = router;
