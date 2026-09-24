const express = require('express');
const router = express.Router();
const websiteController = require('../controllers/websiteController');

// Public route for frontend web
router.get('/data', websiteController.getPublicWebsiteData);

module.exports = router;
