const { db } = require('../config/database');

exports.getWebsiteSettings = (req, res) => {
  try {
    const rows = db.prepare("SELECT key, value FROM settings WHERE key LIKE 'website_%'").all();
    const settings = {};
    rows.forEach(row => {
      settings[row.key] = row.value;
    });
    res.json(settings);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.updateWebsiteSettings = (req, res) => {
  try {
    console.log('Updating website settings:', req.body);
    const { website_about, website_contact_phone, website_contact_email, website_address, website_map_url } = req.body;
    
    const updateStmt = db.prepare("UPDATE settings SET value = ?, updated_at = datetime('now') WHERE key = ?");
    const transaction = db.transaction(() => {
      if (website_about !== undefined) updateStmt.run(website_about, 'website_about');
      if (website_contact_phone !== undefined) updateStmt.run(website_contact_phone, 'website_contact_phone');
      if (website_contact_email !== undefined) updateStmt.run(website_contact_email, 'website_contact_email');
      if (website_address !== undefined) updateStmt.run(website_address, 'website_address');
      if (website_map_url !== undefined) updateStmt.run(website_map_url, 'website_map_url');
    });
    
    transaction();
    res.json({ message: 'Website settings updated successfully' });
  } catch (error) {
    console.error('Update settings error:', error);
    res.status(500).json({ error: error.message });
  }
};

exports.getGeneralSettings = (req, res) => {
  try {
    const keys = ['hijri_adjustment', 'madarsa_open_time', 'madarsa_close_time', 'late_grace_minutes'];
    const placeholders = keys.map(() => '?').join(',');
    const rows = db.prepare(`SELECT key, value FROM settings WHERE key IN (${placeholders})`).all(...keys);
    const settings = {};
    rows.forEach(row => {
      settings[row.key] = row.value;
    });
    // Fill defaults if missing
    if (settings['hijri_adjustment'] === undefined) settings['hijri_adjustment'] = '0';
    if (settings['madarsa_open_time'] === undefined) settings['madarsa_open_time'] = '08:00';
    if (settings['madarsa_close_time'] === undefined) settings['madarsa_close_time'] = '17:00';
    if (settings['late_grace_minutes'] === undefined) settings['late_grace_minutes'] = '15';
    res.json(settings);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.updateGeneralSettings = (req, res) => {
  try {
    const { hijri_adjustment, madarsa_open_time, madarsa_close_time, late_grace_minutes } = req.body;
    const updateStmt = db.prepare("UPDATE settings SET value = ?, updated_at = datetime('now') WHERE key = ?");
    
    const transaction = db.transaction(() => {
      if (hijri_adjustment !== undefined) updateStmt.run(hijri_adjustment.toString(), 'hijri_adjustment');
      if (madarsa_open_time !== undefined) updateStmt.run(madarsa_open_time.toString(), 'madarsa_open_time');
      if (madarsa_close_time !== undefined) updateStmt.run(madarsa_close_time.toString(), 'madarsa_close_time');
      if (late_grace_minutes !== undefined) updateStmt.run(late_grace_minutes.toString(), 'late_grace_minutes');
    });
    
    transaction();
    res.json({ success: true, message: 'Settings updated successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ─── Madarsa Shifts CRUD ─────────────────────────────────────────────
const { v4: uuidv4 } = require('uuid');

exports.getShifts = (req, res) => {
  try {
    const shifts = db.prepare('SELECT * FROM madarsa_shifts WHERE is_active = 1 ORDER BY sort_order ASC').all();
    res.json(shifts);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createShift = (req, res) => {
  try {
    const { shift_name, start_time, end_time } = req.body;
    if (!shift_name || !start_time || !end_time) {
      return res.status(400).json({ error: 'shift_name, start_time, and end_time are required' });
    }
    // Get max sort_order
    const maxOrder = db.prepare('SELECT MAX(sort_order) as max_order FROM madarsa_shifts').get()?.max_order || 0;
    const id = uuidv4();
    db.prepare('INSERT INTO madarsa_shifts (id, shift_name, start_time, end_time, sort_order) VALUES (?, ?, ?, ?, ?)')
      .run(id, shift_name, start_time, end_time, maxOrder + 1);
    res.status(201).json({ id, shift_name, start_time, end_time, sort_order: maxOrder + 1 });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.updateShift = (req, res) => {
  try {
    const { id } = req.params;
    const { shift_name, start_time, end_time, sort_order } = req.body;
    const updates = [];
    const values = [];
    if (shift_name !== undefined) { updates.push('shift_name = ?'); values.push(shift_name); }
    if (start_time !== undefined) { updates.push('start_time = ?'); values.push(start_time); }
    if (end_time !== undefined) { updates.push('end_time = ?'); values.push(end_time); }
    if (sort_order !== undefined) { updates.push('sort_order = ?'); values.push(sort_order); }
    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    values.push(id);
    const info = db.prepare(`UPDATE madarsa_shifts SET ${updates.join(', ')} WHERE id = ?`).run(...values);
    if (info.changes === 0) return res.status(404).json({ error: 'Shift not found' });
    res.json({ success: true, message: 'Shift updated successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteShift = (req, res) => {
  try {
    const { id } = req.params;
    const info = db.prepare('DELETE FROM madarsa_shifts WHERE id = ?').run(id);
    if (info.changes === 0) return res.status(404).json({ error: 'Shift not found' });
    res.json({ success: true, message: 'Shift deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

