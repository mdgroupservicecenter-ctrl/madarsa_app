const express = require('express');
const router = express.Router();
const galleryController = require('../controllers/galleryController');
const upload = require('../middleware/upload');
const { authenticateToken, requirePermission } = require('../middleware/auth');

router.use(authenticateToken);

// Assuming Gallery will be managed under settings for now, or we can make a dedicated module.
// But we don't have 'gallery' in our RBAC modules yet. 
// For now, let's allow users with 'settings' 'view'/'edit' to manage gallery.
// Or we can just use a more generic admin check by not strictly enforcing action, but we will.
router.get('/', requirePermission('settings', 'view'), galleryController.getGallery);
router.post('/', requirePermission('settings', 'edit'), upload.single('image'), galleryController.uploadImage);
router.delete('/:id', requirePermission('settings', 'edit'), galleryController.deleteImage);

module.exports = router;
