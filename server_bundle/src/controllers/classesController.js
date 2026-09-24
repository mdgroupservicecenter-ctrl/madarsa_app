const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

exports.getAllClasses = (req, res) => {
  try {
    const classes = db.prepare(`
      SELECT c.*, 
             d.name as department_name,
             d.parent_id as department_parent_id,
             p.name as parent_department_name
      FROM classes c
      LEFT JOIN departments d ON c.department_id = d.id
      LEFT JOIN departments p ON d.parent_id = p.id
      WHERE c.is_active = 1
      ORDER BY c.created_at DESC
    `).all();
    res.json(classes);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createClass = (req, res) => {
  try {
    const { name, description, duration, department_id } = req.body;
    if (!name) return res.status(400).json({ error: 'Name is required' });

    const trimmedName = name.trim();

    // Check if class with same name already exists IN THE SAME DEPARTMENT
    if (department_id) {
      const existingInSameDept = db.prepare(
        'SELECT id FROM classes WHERE name = ? AND department_id = ? AND is_active = 1'
      ).get(trimmedName, department_id);
      if (existingInSameDept) {
        return res.status(400).json({ error: 'Class name already exists in this department' });
      }
    }

    const id = uuidv4();
    const insert = db.prepare('INSERT INTO classes (id, name, description, duration, department_id) VALUES (?, ?, ?, ?, ?)');
    insert.run(id, trimmedName, description || null, duration || null, department_id || null);
    
    res.status(201).json({ id, name: trimmedName, description, duration, department_id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.updateClass = (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, duration, department_id, is_active } = req.body;
    
    let updates = [];
    let values = [];
    
    if (name !== undefined) { updates.push('name = ?'); values.push(name.trim()); }
    if (description !== undefined) { updates.push('description = ?'); values.push(description); }
    if (duration !== undefined) { updates.push('duration = ?'); values.push(duration); }
    if (department_id !== undefined) { updates.push('department_id = ?'); values.push(department_id); }
    if (is_active !== undefined) { updates.push('is_active = ?'); values.push(is_active ? 1 : 0); }
    
    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    
    values.push(id);
    const sql = `UPDATE classes SET ${updates.join(', ')} WHERE id = ?`;
    
    const info = db.prepare(sql).run(...values);
    if (info.changes === 0) return res.status(404).json({ error: 'Class not found' });
    
    res.json({ message: 'Class updated successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteClass = (req, res) => {
  try {
    const { id } = req.params;
    const info = db.prepare('DELETE FROM classes WHERE id = ?').run(id);
    if (info.changes === 0) return res.status(404).json({ error: 'Class not found' });
    res.json({ message: 'Class deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
