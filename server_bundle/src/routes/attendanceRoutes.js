const express = require('express');
const router = express.Router();
const attendanceController = require('../controllers/attendanceController');
const { authenticateToken } = require('../middleware/auth');

router.use(authenticateToken);

router.get('/students', attendanceController.getStudentAttendance);
router.get('/student/:studentId', attendanceController.getAttendanceByStudentId);
router.get('/students/:studentId', attendanceController.getAttendanceByStudentId);
router.post('/students', attendanceController.saveStudentAttendance);
router.post('/students/auto-save', attendanceController.saveSingleStudentAttendance);

router.get('/staff', attendanceController.getStaffAttendance);
router.post('/staff', attendanceController.saveStaffAttendance);

router.post('/biometric/scan', attendanceController.biometricScan);
router.post('/biometric/enroll', attendanceController.biometricEnroll);
router.post('/biometric/clear', attendanceController.clearBiometric);

// Period Attendance routes
router.get('/periods', attendanceController.getPeriodAttendance);
router.post('/periods/auto-save', attendanceController.saveSinglePeriodAttendance);
router.post('/periods/bulk', attendanceController.bulkPeriodAttendance);

module.exports = router;
