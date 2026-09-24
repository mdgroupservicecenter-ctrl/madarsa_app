const { db } = require('../config/database');

exports.getPublicWebsiteData = (req, res) => {
  try {
    // 1. Get Settings
    const settingRows = db.prepare("SELECT key, value FROM settings WHERE key LIKE 'website_%'").all();
    const settings = {};
    settingRows.forEach(row => {
      settings[row.key] = row.value;
    });

    // 2. Get Classes
    const classes = db.prepare('SELECT id, name, description, duration FROM classes WHERE is_active = 1 ORDER BY created_at DESC').all();

    // 3. Get Gallery
    const gallery = db.prepare('SELECT id, title, image_path, category FROM gallery ORDER BY created_at DESC').all();

    res.json({
      settings,
      classes,
      gallery
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
