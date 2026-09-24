const express = require('express');
const router = express.Router();
const roleController = require('../controllers/roleController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

router.use(authenticateToken);

router.get('/', requirePermission('roles', 'view'), roleController.getAll);
router.get('/permissions', requirePermission('roles', 'view'), roleController.getAllPermissions);
router.get('/:id', requirePermission('roles', 'view'), roleController.getById);
router.post('/', requirePermission('roles', 'create'), roleController.create);
router.put('/:id', requirePermission('roles', 'edit'), roleController.update);
router.patch('/:id/toggle', requirePermission('roles', 'edit'), roleController.toggleActive);

module.exports = router;
