const express = require('express');
const router = express.Router();
const staffController = require('../controllers/staffController');

// GET next staff no (must be before /:id)
router.get('/next-no', staffController.getNextStaffNo);

// GET stats
router.get('/stats', staffController.getStats);

// Staff Types CRUD (must be before /:id)
router.get('/types', staffController.getStaffTypes);
router.post('/types', staffController.createStaffType);
router.put('/types/:id', staffController.updateStaffType);
router.delete('/types/:id', staffController.deleteStaffType);

// Qualifications CRUD (must be before /:id)
router.get('/qualifications', staffController.getQualifications);
router.post('/qualifications', staffController.createQualification);
router.put('/qualifications/:id', staffController.updateQualification);
router.delete('/qualifications/:id', staffController.deleteQualification);

// GET all staff (with search & filter)
router.get('/', staffController.getAll);

// GET single staff
router.get('/:id', staffController.getById);

// POST create staff
router.post('/', staffController.create);

// PUT update staff
router.put('/:id', staffController.update);

// DELETE staff
router.delete('/:id', staffController.remove);

// POST assign books to staff
router.post('/:id/books', staffController.assignBooks);

// POST bulk delete staff
router.post('/bulk-delete', staffController.bulkDelete);

module.exports = router;
