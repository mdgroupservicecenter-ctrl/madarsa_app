const express = require('express');
const router = express.Router();
const studentController = require('../controllers/studentController');
const { authenticateToken, requirePermission } = require('../middleware/auth');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const uploadDir = path.join(__dirname, '../../uploads/documents');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, 'doc-' + uniqueSuffix + path.extname(file.originalname));
  }
});
const upload = multer({ storage: storage });

router.use(authenticateToken);

router.get('/', requirePermission('students', 'view'), studentController.getAllStudents);
router.get('/search', requirePermission('students', 'view'), studentController.searchStudents);
router.get('/next-gr', requirePermission('students', 'view'), studentController.getNextGRNo);
router.get('/age-calc', requirePermission('students', 'view'), studentController.getAgeCalculation);
router.get('/gr/:grNo', requirePermission('students', 'view'), studentController.getStudentByGRNo);
router.get('/:id', requirePermission('students', 'view'), studentController.getStudentById);
router.post('/', requirePermission('students', 'create'), studentController.createStudent);
router.put('/:id', requirePermission('students', 'edit'), studentController.updateStudent);
router.delete('/:id', requirePermission('students', 'delete'), studentController.deleteStudent);

router.post('/:id/documents', requirePermission('students', 'edit'), upload.single('document'), studentController.uploadDocument);
router.delete('/:id/documents/:documentId', requirePermission('students', 'edit'), studentController.deleteDocument);

router.post('/bulk-assign-category', requirePermission('students', 'edit'), studentController.bulkAssignCategory);
router.post('/bulk-assign-division', requirePermission('students', 'edit'), studentController.bulkAssignDivision);
router.post('/bulk-assign-roll-numbers', requirePermission('students', 'edit'), studentController.bulkAssignRollNumbers);
router.post('/bulk-assign-status', requirePermission('students', 'edit'), studentController.bulkAssignStatus);
router.post('/bulk-delete', requirePermission('students', 'delete'), studentController.bulkDeleteStudents);
router.post('/bulk-promote', requirePermission('students', 'edit'), studentController.bulkPromoteStudents);

// Academic History endpoints
router.get('/:id/academic-history', requirePermission('students', 'view'), studentController.getStudentAcademicHistory);
router.post('/:id/academic-history', requirePermission('students', 'edit'), studentController.createStudentAcademicHistory);
router.delete('/academic-history/:historyId', requirePermission('students', 'edit'), studentController.deleteStudentAcademicHistory);

// Pin Code & Village endpoints
router.get('/pin-code/:pinCode', requirePermission('students', 'view'), studentController.getPinCodeDetails);
router.get('/villages/search', requirePermission('students', 'view'), studentController.searchVillages);
router.get('/pin-codes', requirePermission('students', 'view'), studentController.getAllPinCodes);

module.exports = router;
