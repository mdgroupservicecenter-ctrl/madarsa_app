const express = require('express');
const router = express.Router();
const contributorController = require('../controllers/contributorController');
const { authenticateToken } = require('../middleware/auth');
const { requirePermission } = require('../middleware/auth');

router.use(authenticateToken);

router.get('/', requirePermission('students', 'view'), contributorController.getAllContributors);
router.get('/:id', requirePermission('students', 'view'), contributorController.getContributorById);
router.post('/', requirePermission('students', 'create'), contributorController.createContributor);
router.put('/:id', requirePermission('students', 'edit'), contributorController.updateContributor);
router.delete('/:id', requirePermission('students', 'delete'), contributorController.deleteContributor);

module.exports = router;
