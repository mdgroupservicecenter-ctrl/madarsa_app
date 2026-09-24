const express = require('express');
const router = express.Router();
const examController = require('../controllers/examController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

// Exams CRUD
router.get('/', authenticateToken, requirePermission('exams', 'view'), examController.getAllExams);
router.post('/', authenticateToken, requirePermission('exams', 'create'), examController.createExam);
router.put('/:id', authenticateToken, requirePermission('exams', 'edit'), examController.updateExam);
router.delete('/:id', authenticateToken, requirePermission('exams', 'delete'), examController.deleteExam);

// Exam Schedules
router.get('/:exam_id/schedules', authenticateToken, requirePermission('exams', 'view'), examController.getExamSchedules);
router.post('/schedules', authenticateToken, requirePermission('exams', 'create'), examController.createExamSchedule);
router.put('/schedules/:id', authenticateToken, requirePermission('exams', 'edit'), examController.updateExamSchedule);
router.delete('/schedules/:id', authenticateToken, requirePermission('exams', 'delete'), examController.deleteExamSchedule);

// Exam Halls
router.get('/halls', authenticateToken, requirePermission('exams', 'view'), examController.getAllHalls);
router.post('/halls', authenticateToken, requirePermission('exams', 'create'), examController.createHall);
router.put('/halls/:id', authenticateToken, requirePermission('exams', 'edit'), examController.updateHall);
router.delete('/halls/:id', authenticateToken, requirePermission('exams', 'delete'), examController.deleteHall);

// Seating
router.post('/seating/generate', authenticateToken, requirePermission('exams', 'create'), examController.generateSeating);
router.get('/:exam_id/seating', authenticateToken, requirePermission('exams', 'view'), examController.getSeatingArrangements);

// Results
router.get('/:exam_id/results', authenticateToken, requirePermission('exams', 'view'), examController.getResults);
router.post('/results', authenticateToken, requirePermission('exams', 'create'), examController.saveResult);
router.put('/results/:id', authenticateToken, requirePermission('exams', 'edit'), examController.updateResult);
router.delete('/results/:id', authenticateToken, requirePermission('exams', 'delete'), examController.deleteResult);

module.exports = router;
