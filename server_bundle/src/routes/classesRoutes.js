const express = require('express');
const router = express.Router();
const classesController = require('../controllers/classesController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

router.use(authenticateToken);

router.get('/', requirePermission('classes', 'view'), classesController.getAllClasses);
router.post('/', requirePermission('classes', 'create'), classesController.createClass);
router.put('/:id', requirePermission('classes', 'edit'), classesController.updateClass);
router.delete('/:id', requirePermission('classes', 'delete'), classesController.deleteClass);

module.exports = router;
