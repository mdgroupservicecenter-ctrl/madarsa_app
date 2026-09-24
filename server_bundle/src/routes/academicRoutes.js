const express = require('express');
const router = express.Router();
const academicController = require('../controllers/academicController');
const { authenticateToken } = require('../middleware/auth');
const { requirePermission } = require('../middleware/auth');

// Using similar RBAC as classes module 'classes' for simplicity, or we could add real permissions
router.use(authenticateToken);

// --- Departments ---
router.get('/departments', requirePermission('classes', 'view'), academicController.getAllDepartments);
router.post('/departments', requirePermission('classes', 'create'), academicController.createDepartment);
router.put('/departments/:id', requirePermission('classes', 'edit'), academicController.updateDepartment);
router.delete('/departments/:id', requirePermission('classes', 'delete'), academicController.deleteDepartment);

// --- Hierarchy Query ---
router.get('/hierarchy', requirePermission('classes', 'view'), academicController.getAcademicHierarchy);

// --- Courses ---
router.get('/courses', requirePermission('classes', 'view'), academicController.getAllCourses);
router.post('/courses', requirePermission('classes', 'create'), academicController.createCourse);
router.put('/courses/:id', requirePermission('classes', 'edit'), academicController.updateCourse);
router.delete('/courses/:id', requirePermission('classes', 'delete'), academicController.deleteCourse);

// --- Books ---
router.get('/books', requirePermission('classes', 'view'), academicController.getAllBooks);
router.post('/books', requirePermission('classes', 'create'), academicController.createBook);
router.put('/books/:id', requirePermission('classes', 'edit'), academicController.updateBook);
router.delete('/books/:id', requirePermission('classes', 'delete'), academicController.deleteBook);

// --- Mappings ---
router.post('/mappings/class-course', requirePermission('classes', 'create'), academicController.assignCourseToClass);
router.delete('/mappings/class-course/:id', requirePermission('classes', 'delete'), academicController.removeCourseFromClass);

router.post('/mappings/course-book', requirePermission('classes', 'create'), academicController.assignBookToClassCourse);
router.delete('/mappings/course-book/:id', requirePermission('classes', 'delete'), academicController.removeBookFromClassCourse);

// --- Class Book Periods ---
router.get('/class-periods', requirePermission('classes', 'view'), academicController.getClassBookPeriods);
router.post('/class-periods', requirePermission('classes', 'create'), academicController.saveClassBookPeriod);
router.delete('/class-periods/:id', requirePermission('classes', 'delete'), academicController.deleteClassBookPeriod);

module.exports = router;
