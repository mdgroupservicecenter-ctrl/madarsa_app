const express = require('express');
const router = express.Router();
const userController = require('../controllers/userController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

router.use(authenticateToken);

router.get('/', requirePermission('users', 'view'), userController.getAll);
router.get('/:id', requirePermission('users', 'view'), userController.getById);
router.post('/', requirePermission('users', 'create'), userController.create);
router.put('/:id', requirePermission('users', 'edit'), userController.update);
router.put('/:id/reset-password', requirePermission('users', 'edit'), userController.resetPassword);

module.exports = router;
