const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');

exports.getGallery = (req, res) => {
  try {
    const images = db.prepare('SELECT * FROM gallery ORDER BY created_at DESC').all();
    res.json(images);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.uploadImage = (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file uploaded' });
    }

    const { title, category } = req.body;
    const image_path = '/uploads/gallery/' + req.file.filename;

    const id = uuidv4();
    const insert = db.prepare('INSERT INTO gallery (id, title, image_path, category) VALUES (?, ?, ?, ?)');
    insert.run(id, title || 'Untitled', image_path, category || 'General');

    res.status(201).json({ id, title, image_path, category });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteImage = (req, res) => {
  try {
    const { id } = req.params;
    
    // First get the image path to delete the physical file
    const image = db.prepare('SELECT image_path FROM gallery WHERE id = ?').get(id);
    if (!image) {
      return res.status(404).json({ error: 'Image not found' });
    }

    // Delete from DB
    db.prepare('DELETE FROM gallery WHERE id = ?').run(id);

    // Delete physical file
    const fullPath = path.join(__dirname, '../../..', image.image_path);
    if (fs.existsSync(fullPath)) {
      fs.unlinkSync(fullPath);
    }

    res.json({ message: 'Image deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
