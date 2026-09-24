const express = require('express');
const router = express.Router();
const hostelController = require('../controllers/hostelController');
const { authenticateToken, requirePermission } = require('../middleware/auth');

// Secure all hostel routes with token authentication
router.use(authenticateToken);

// ─── Hostel Routes ──────────────────────────────────────────────────
router.get('/hostels', requirePermission('hostel', 'view'), hostelController.getHostels);
router.post('/hostels', requirePermission('hostel', 'create'), hostelController.createHostel);
router.put('/hostels/:id', requirePermission('hostel', 'edit'), hostelController.updateHostel);
router.delete('/hostels/:id', requirePermission('hostel', 'delete'), hostelController.deleteHostel);

// ─── Room Routes ────────────────────────────────────────────────────
router.get('/rooms', requirePermission('hostel', 'view'), hostelController.getRooms);
router.post('/rooms', requirePermission('hostel', 'create'), hostelController.createRoom);
router.put('/rooms/:id', requirePermission('hostel', 'edit'), hostelController.updateRoom);
router.delete('/rooms/:id', requirePermission('hostel', 'delete'), hostelController.deleteRoom);

// ─── Bed Routes ─────────────────────────────────────────────────────
router.get('/beds', requirePermission('hostel', 'view'), hostelController.getBeds);
router.post('/beds', requirePermission('hostel', 'create'), hostelController.createBed);
router.delete('/beds/:id', requirePermission('hostel', 'delete'), hostelController.deleteBed);

// ─── Allocations / Stay Records Routes ──────────────────────────────
router.get('/allocations', requirePermission('hostel', 'view'), hostelController.getAllocations);
router.post('/allocations/bulk', requirePermission('hostel', 'create'), hostelController.bulkAllocateRoom);
router.post('/allocations', requirePermission('hostel', 'create'), hostelController.allocateRoom);
router.put('/allocations/:id/vacate', requirePermission('hostel', 'edit'), hostelController.vacateRoom);
router.delete('/allocations/:id', requirePermission('hostel', 'delete'), hostelController.deleteAllocation);

module.exports = router;
