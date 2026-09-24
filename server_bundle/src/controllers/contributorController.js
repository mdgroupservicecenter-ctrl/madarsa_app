const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

exports.getAllContributors = (req, res) => {
  try {
    const contributors = db.prepare('SELECT * FROM contributors ORDER BY name ASC').all();

    // Enrich each contributor with aggregated stats
    const enriched = contributors.map(c => {
      const stats = db.prepare(`
        SELECT COUNT(*) as totalStudentsHelped, 
               COALESCE(SUM(contributor_amount), 0) as totalContributionAmount
        FROM students 
        WHERE contributor_id = ? AND is_active = 1
      `).get(c.id);

      return {
        ...c,
        totalStudentsHelped: stats.totalStudentsHelped || 0,
        totalContributionAmount: stats.totalContributionAmount || 0,
      };
    });

    res.json(enriched);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching contributors', error: error.message });
  }
};

exports.getContributorById = (req, res) => {
  try {
    const { id } = req.params;
    const contributor = db.prepare('SELECT * FROM contributors WHERE id = ?').get(id);
    
    if (!contributor) {
      return res.status(404).json({ message: 'Contributor not found' });
    }

    // Fetch sponsored students
    const sponsoredStudents = db.prepare(`
      SELECT id, gr_no, full_name, father_name, surname, class_name, condition_type, contributor_amount 
      FROM students 
      WHERE contributor_id = ? AND is_active = 1
      ORDER BY full_name ASC
    `).all(id);

    // Calculate aggregated stats
    const totalStudentsHelped = sponsoredStudents.length;
    const totalContributionAmount = sponsoredStudents.reduce((sum, s) => sum + (s.contributor_amount || 0), 0);

    res.json({
      ...contributor,
      sponsoredStudents,
      totalStudentsHelped,
      totalContributionAmount
    });
  } catch (error) {
    res.status(500).json({ message: 'Error fetching contributor details', error: error.message });
  }
};

exports.createContributor = (req, res) => {
  try {
    const { name, phone, email, address } = req.body;
    
    if (!name) {
      return res.status(400).json({ message: 'Contributor Name is required' });
    }

    if (!phone) {
      return res.status(400).json({ message: 'Phone/Mobile number is required' });
    }

    const cleanedPhone = phone.trim().replace(/\D/g, '');
    if (cleanedPhone.length !== 10) {
      return res.status(400).json({ message: 'Mobile number must be exactly 10 digits' });
    }

    const existingPhone = db.prepare('SELECT id FROM contributors WHERE phone = ?').get(cleanedPhone);
    if (existingPhone) {
      return res.status(400).json({ message: 'Contributor with this mobile number already exists' });
    }

    const id = uuidv4();
    const stmt = db.prepare(`
      INSERT INTO contributors (id, name, phone, email, address)
      VALUES (?, ?, ?, ?, ?)
    `);

    stmt.run(id, name, cleanedPhone, email || null, address || null);

    res.status(201).json({
      success: true,
      message: 'Contributor created successfully',
      data: { id, name, phone: cleanedPhone, email, address }
    });
  } catch (error) {
    res.status(500).json({ message: 'Error creating contributor', error: error.message });
  }
};

exports.updateContributor = (req, res) => {
  try {
    const { id } = req.params;
    const { name, phone, email, address } = req.body;

    const existing = db.prepare('SELECT * FROM contributors WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Contributor not found' });
    }

    let cleanedPhone = existing.phone;
    if (phone !== undefined) {
      if (!phone) {
        return res.status(400).json({ message: 'Phone/Mobile number is required' });
      }
      cleanedPhone = phone.trim().replace(/\D/g, '');
      if (cleanedPhone.length !== 10) {
        return res.status(400).json({ message: 'Mobile number must be exactly 10 digits' });
      }
      const existingPhone = db.prepare('SELECT id FROM contributors WHERE phone = ? AND id != ?').get(cleanedPhone, id);
      if (existingPhone) {
        return res.status(400).json({ message: 'Contributor with this mobile number already exists' });
      }
    }

    const stmt = db.prepare(`
      UPDATE contributors
      SET name = COALESCE(?, name),
          phone = ?,
          email = ?,
          address = ?,
          updated_at = datetime('now')
      WHERE id = ?
    `);

    stmt.run(name, cleanedPhone, email || null, address || null, id);

    res.json({
      success: true,
      message: 'Contributor updated successfully',
      data: { id, name: name || existing.name, phone: cleanedPhone, email, address }
    });
  } catch (error) {
    res.status(500).json({ message: 'Error updating contributor', error: error.message });
  }
};

exports.deleteContributor = (req, res) => {
  try {
    const { id } = req.params;
    
    const existing = db.prepare('SELECT * FROM contributors WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Contributor not found' });
    }

    // Wrap in database transaction to clear links on students table before deleting contributor
    const transaction = db.transaction(() => {
      // Reset contributor links on associated students
      db.prepare(`
        UPDATE students
        SET contributor_id = NULL,
            contributor_amount = 0,
            condition_type = 'Regular',
            updated_at = datetime('now')
        WHERE contributor_id = ?
      `).run(id);

      // Delete the contributor
      db.prepare('DELETE FROM contributors WHERE id = ?').run(id);
    });

    transaction();

    res.json({ success: true, message: 'Contributor deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting contributor', error: error.message });
  }
};
