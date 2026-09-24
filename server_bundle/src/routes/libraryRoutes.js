const express = require('express');
const router = express.Router();
const libraryController = require('../controllers/libraryController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

// Secure all library routes with token authentication
router.use(authenticateToken);

// ─── Settings ────────────────────────────────────────────────────────
router.get('/settings', requirePermission('library', 'view'), libraryController.getSettings);
router.put('/settings', requirePermission('library', 'edit'), libraryController.updateSettings);

// ─── Categories ──────────────────────────────────────────────────────
router.get('/categories', requirePermission('library', 'view'), libraryController.getCategories);
router.post('/categories', requirePermission('library', 'create'), libraryController.createCategory);
router.put('/categories/:id', requirePermission('library', 'edit'), libraryController.updateCategory);
router.delete('/categories/:id', requirePermission('library', 'delete'), libraryController.deleteCategory);

// ─── Books ───────────────────────────────────────────────────────────
router.get('/books', requirePermission('library', 'view'), libraryController.getBooks);
router.post('/books', requirePermission('library', 'create'), libraryController.createBook);
router.put('/books/:id', requirePermission('library', 'edit'), libraryController.updateBook);
router.delete('/books/:id', requirePermission('library', 'delete'), libraryController.deleteBook);

// ─── Transactions ────────────────────────────────────────────────────
router.get('/transactions', requirePermission('library', 'view'), libraryController.getTransactions);
router.post('/transactions/issue', requirePermission('library', 'create'), libraryController.issueBook);
router.put('/transactions/:id/return', requirePermission('library', 'edit'), libraryController.returnBook);
router.put('/transactions/:id/lost', requirePermission('library', 'edit'), libraryController.markBookLost);
router.put('/transactions/:id', requirePermission('library', 'edit'), libraryController.updateTransaction);
router.delete('/transactions/:id', requirePermission('library', 'delete'), libraryController.deleteTransaction);

// ─── Stats & Borrowing History ───────────────────────────────────────
router.get('/stats', requirePermission('library', 'view'), libraryController.getStats);
router.get('/student/:studentId/history', requirePermission('library', 'view'), libraryController.getStudentHistory);

module.exports = router;
