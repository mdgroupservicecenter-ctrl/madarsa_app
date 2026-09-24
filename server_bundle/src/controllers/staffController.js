const { v4: uuidv4 } = require('uuid');
const db = require('../config/database').getDb ? require('../config/database').getDb() : require('../config/database').db;

// ──────────────────────────────────────────────────────────────────────────────
// Helper: get db reference
// ──────────────────────────────────────────────────────────────────────────────
function getDb() {
  return require('../config/database').db;
}

// ──────────────────────────────────────────────────────────────────────────────
// GET /api/staff/next-no
// ──────────────────────────────────────────────────────────────────────────────
exports.getNextStaffNo = (req, res) => {
  try {
    const database = getDb();
    const row = database
      .prepare("SELECT staff_no FROM staff ORDER BY staff_no DESC LIMIT 1")
      .get();

    let nextNo = 'S-0001';
    if (row && row.staff_no) {
      const parts = row.staff_no.split('-');
      const num = parseInt(parts[1] || '0', 10) + 1;
      nextNo = `S-${String(num).padStart(4, '0')}`;
    }
    res.json({ staff_no: nextNo });
  } catch (err) {
    console.error('getNextStaffNo error:', err);
    res.status(500).json({ error: err.message });
  }
};

// ──────────────────────────────────────────────────────────────────────────────
// GET /api/staff
// ──────────────────────────────────────────────────────────────────────────────
exports.getAll = (req, res) => {
  try {
    const database = getDb();
    const { q, staff_type, is_active } = req.query;

    let sql = `SELECT s.*, r.name as role_name 
               FROM staff s 
               LEFT JOIN roles r ON s.role_id = r.id 
               WHERE 1=1`;
    const params = [];

    if (q) {
      sql += ` AND (s.full_name LIKE ? OR s.staff_no LIKE ? OR s.father_name LIKE ? OR s.mobile_no LIKE ? OR s.staff_type LIKE ?)`;
      const likeQ = `%${q}%`;
      params.push(likeQ, likeQ, likeQ, likeQ, likeQ);
    }
    if (staff_type) {
      sql += ` AND s.staff_type = ?`;
      params.push(staff_type);
    }
    if (is_active !== undefined) {
      sql += ` AND s.is_active = ?`;
      params.push(is_active === 'true' ? 1 : 0);
    }

    sql += ` ORDER BY s.created_at DESC`;

    const rows = database.prepare(sql).all(...params);

    const assignedBooksRaw = database.prepare(`
       SELECT sb.staff_id, b.id as book_id, b.name as book_name, c.name as course_name, cl.name as class_name, sb.course_book_id
       FROM staff_books sb
       JOIN course_books cb ON sb.course_book_id = cb.id
       JOIN books b ON cb.book_id = b.id
       JOIN class_courses cc ON cb.class_course_id = cc.id
       JOIN courses c ON cc.course_id = c.id
       JOIN classes cl ON cc.class_id = cl.id
    `).all();

    const booksMap = {};
    for (const b of assignedBooksRaw) {
      if (!booksMap[b.staff_id]) booksMap[b.staff_id] = [];
      booksMap[b.staff_id].push(b);
    }
    
    for (let i = 0; i < rows.length; i++) {
       rows[i].assigned_books = booksMap[rows[i].id] || [];
    }

    res.json({ data: rows, total: rows.length });
  } catch (err) {
    console.error('Staff getAll error:', err);
    res.status(500).json({ error: err.message });
  }
};

// ──────────────────────────────────────────────────────────────────────────────
// GET /api/staff/:id
// ──────────────────────────────────────────────────────────────────────────────
exports.getById = (req, res) => {
  try {
    const database = getDb();
    const staff = database
      .prepare(`SELECT s.*, r.name as role_name FROM staff s 
                LEFT JOIN roles r ON s.role_id = r.id 
                WHERE s.id = ?`)
      .get(req.params.id);

    if (!staff) return res.status(404).json({ error: 'Staff not found' });

    // Get documents
    const docs = database
      .prepare('SELECT * FROM staff_documents WHERE staff_id = ?')
      .all(req.params.id);

    const assignedBooks = database.prepare(`
       SELECT sb.staff_id, b.id as book_id, b.name as book_name, c.name as course_name, cl.name as class_name, sb.course_book_id
       FROM staff_books sb
       JOIN course_books cb ON sb.course_book_id = cb.id
       JOIN books b ON cb.book_id = b.id
       JOIN class_courses cc ON cb.class_course_id = cc.id
       JOIN courses c ON cc.course_id = c.id
       JOIN classes cl ON cc.class_id = cl.id
       WHERE sb.staff_id = ?
    `).all(req.params.id);

    res.json({ ...staff, documents: docs, assigned_books: assignedBooks });
  } catch (err) {
    console.error('Staff getById error:', err);
    res.status(500).json({ error: err.message });
  }
};

// ──────────────────────────────────────────────────────────────────────────────
// POST /api/staff
// ──────────────────────────────────────────────────────────────────────────────
exports.create = (req, res) => {
  try {
    const database = getDb();
    const {
      staff_no,
      full_name,
      father_name,
      surname,
      date_of_birth,
      gender,
      staff_type,
      qualification,
      experience_years,
      joining_date,
      joining_date_h,
      salary,
      mobile_no,
      aadhaar_no,
      village,
      taluka,
      district,
      state,
      pin_code,
      emergency_contact,
      address,
      is_active,
      note,
      role_id,
      user_id,
      photo_path,
    } = req.body;

    if (!full_name || !staff_type) {
      return res.status(400).json({ error: 'full_name and staff_type are required' });
    }

    // Auto generate staff_no if not provided
    let finalStaffNo = staff_no;
    if (!finalStaffNo) {
      const row = database
        .prepare("SELECT staff_no FROM staff ORDER BY staff_no DESC LIMIT 1")
        .get();
      if (row && row.staff_no) {
        const parts = row.staff_no.split('-');
        const num = parseInt(parts[1] || '0', 10) + 1;
        finalStaffNo = `S-${String(num).padStart(4, '0')}`;
      } else {
        finalStaffNo = 'S-0001';
      }
    }

    const id = uuidv4();
    const now = new Date().toISOString();

    database.prepare(`
      INSERT INTO staff (
        id, staff_no, full_name, father_name, surname, date_of_birth, gender,
        staff_type, qualification, experience_years, joining_date, joining_date_h,
        salary, mobile_no, aadhaar_no, village, taluka, district, state, pin_code,
        emergency_contact, address, is_active, note, role_id, user_id, photo_path,
        created_at, updated_at
      ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
      )
    `).run(
      id, finalStaffNo, full_name, father_name || null, surname || null,
      date_of_birth || null, gender || null, staff_type,
      qualification || null, experience_years || 0,
      joining_date || null, joining_date_h || null,
      salary || 0, mobile_no || null, aadhaar_no || null,
      village || null, taluka || null, district || null,
      state || null, pin_code || null, emergency_contact || null,
      address || null, is_active !== undefined ? (is_active ? 1 : 0) : 1,
      note || null, role_id || null, user_id || null,
      photo_path || null, now, now,
    );

    // Log activity
    try {
      database.prepare(`
        INSERT INTO activity_logs (id, user_id, action, module, details, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(uuidv4(), req.user?.id || null, 'create', 'staff', 
             `Added staff: ${full_name} (${finalStaffNo})`, now);
    } catch (_) {}

    const created = database.prepare('SELECT * FROM staff WHERE id = ?').get(id);
    res.status(201).json({ message: 'Staff added successfully', data: created });
  } catch (err) {
    console.error('Staff create error:', err);
    if (err.message.includes('UNIQUE constraint failed')) {
      return res.status(400).json({ error: 'Staff No. already exists' });
    }
    res.status(500).json({ error: err.message });
  }
};

// ──────────────────────────────────────────────────────────────────────────────
// PUT /api/staff/:id
// ──────────────────────────────────────────────────────────────────────────────
exports.update = (req, res) => {
  try {
    const database = getDb();
    const existing = database
      .prepare('SELECT * FROM staff WHERE id = ?')
      .get(req.params.id);
    if (!existing) return res.status(404).json({ error: 'Staff not found' });

    const {
      full_name, father_name, surname, date_of_birth, gender, staff_type,
      qualification, experience_years, joining_date, joining_date_h,
      salary, mobile_no, aadhaar_no, village, taluka, district, state, pin_code,
      emergency_contact, address, is_active, note, role_id, user_id, photo_path,
    } = req.body;

    const now = new Date().toISOString();
    database.prepare(`
      UPDATE staff SET
        full_name = ?, father_name = ?, surname = ?, date_of_birth = ?, gender = ?,
        staff_type = ?, qualification = ?, experience_years = ?, joining_date = ?,
        joining_date_h = ?, salary = ?, mobile_no = ?, aadhaar_no = ?, village = ?,
        taluka = ?, district = ?, state = ?, pin_code = ?, emergency_contact = ?,
        address = ?, is_active = ?, note = ?, role_id = ?, user_id = ?,
        photo_path = ?, updated_at = ?
      WHERE id = ?
    `).run(
      full_name || existing.full_name,
      father_name ?? existing.father_name,
      surname ?? existing.surname,
      date_of_birth ?? existing.date_of_birth,
      gender ?? existing.gender,
      staff_type || existing.staff_type,
      qualification ?? existing.qualification,
      experience_years ?? existing.experience_years,
      joining_date ?? existing.joining_date,
      joining_date_h ?? existing.joining_date_h,
      salary ?? existing.salary,
      mobile_no ?? existing.mobile_no,
      aadhaar_no ?? existing.aadhaar_no,
      village ?? existing.village,
      taluka ?? existing.taluka,
      district ?? existing.district,
      state ?? existing.state,
      pin_code ?? existing.pin_code,
      emergency_contact ?? existing.emergency_contact,
      address ?? existing.address,
      is_active !== undefined ? (is_active ? 1 : 0) : existing.is_active,
      note ?? existing.note,
      role_id ?? existing.role_id,
      user_id ?? existing.user_id,
      photo_path ?? existing.photo_path,
      now,
      req.params.id,
    );

    // Log
    try {
      database.prepare(`
        INSERT INTO activity_logs (id, user_id, action, module, details, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(uuidv4(), req.user?.id || null, 'update', 'staff',
             `Updated staff: ${full_name || existing.full_name}`, now);
    } catch (_) {}

    const updated = database.prepare('SELECT * FROM staff WHERE id = ?').get(req.params.id);
    res.json({ message: 'Staff updated successfully', data: updated });
  } catch (err) {
    console.error('Staff update error:', err);
    res.status(500).json({ error: err.message });
  }
};

// ──────────────────────────────────────────────────────────────────────────────
// DELETE /api/staff/:id
// ──────────────────────────────────────────────────────────────────────────────
exports.remove = (req, res) => {
  try {
    const database = getDb();
    const staff = database
      .prepare('SELECT * FROM staff WHERE id = ?')
      .get(req.params.id);
    if (!staff) return res.status(404).json({ error: 'Staff not found' });

    database.prepare('DELETE FROM staff WHERE id = ?').run(req.params.id);

    // Log
    try {
      const now = new Date().toISOString();
      database.prepare(`
        INSERT INTO activity_logs (id, user_id, action, module, details, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(uuidv4(), req.user?.id || null, 'delete', 'staff',
             `Deleted staff: ${staff.full_name} (${staff.staff_no})`, now);
    } catch (_) {}

    res.json({ message: 'Staff deleted successfully' });
  } catch (err) {
    console.error('Staff remove error:', err);
    res.status(500).json({ error: err.message });
  }
};

// ──────────────────────────────────────────────────────────────────────────────
// GET /api/staff/stats
// ──────────────────────────────────────────────────────────────────────────────
exports.getStats = (req, res) => {
  try {
    const database = getDb();
    const total = database.prepare('SELECT COUNT(*) as c FROM staff').get().c;
    const active = database.prepare('SELECT COUNT(*) as c FROM staff WHERE is_active = 1').get().c;
    const teachers = database.prepare("SELECT COUNT(*) as c FROM staff WHERE staff_type = 'Teacher'").get().c;
    const byType = database.prepare(`
      SELECT staff_type, COUNT(*) as count FROM staff GROUP BY staff_type
    `).all();

    res.json({ total, active, teachers, byType });
  } catch (err) {
    console.error('Staff stats error:', err);
    res.status(500).json({ error: err.message });
  }
};

// ══════════════════════════════════════════════════════════════════════════════
// STAFF TYPES MANAGEMENT
// ══════════════════════════════════════════════════════════════════════════════

// GET /api/staff/types
exports.getStaffTypes = (req, res) => {
  try {
    const database = getDb();
    const types = database.prepare(
      'SELECT * FROM staff_types WHERE is_active = 1 ORDER BY name'
    ).all();
    res.json(types);
  } catch (err) {
    console.error('getStaffTypes error:', err);
    res.status(500).json({ error: err.message });
  }
};

// POST /api/staff/types
exports.createStaffType = (req, res) => {
  try {
    const database = getDb();
    const { name, description } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }
    const id = uuidv4();
    database.prepare(
      'INSERT INTO staff_types (id, name, description) VALUES (?, ?, ?)'
    ).run(id, name.trim(), description || null);

    const created = database.prepare('SELECT * FROM staff_types WHERE id = ?').get(id);
    res.status(201).json({ message: 'Staff type added', data: created });
  } catch (err) {
    if (err.message.includes('UNIQUE constraint')) {
      return res.status(400).json({ error: 'This staff type already exists' });
    }
    console.error('createStaffType error:', err);
    res.status(500).json({ error: err.message });
  }
};

// PUT /api/staff/types/:id
exports.updateStaffType = (req, res) => {
  try {
    const database = getDb();
    const { name, description } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }
    database.prepare(
      'UPDATE staff_types SET name = ?, description = ? WHERE id = ?'
    ).run(name.trim(), description || null, req.params.id);

    const updated = database.prepare('SELECT * FROM staff_types WHERE id = ?').get(req.params.id);
    res.json({ message: 'Staff type updated', data: updated });
  } catch (err) {
    if (err.message.includes('UNIQUE constraint')) {
      return res.status(400).json({ error: 'This staff type already exists' });
    }
    console.error('updateStaffType error:', err);
    res.status(500).json({ error: err.message });
  }
};

// DELETE /api/staff/types/:id
exports.deleteStaffType = (req, res) => {
  try {
    const database = getDb();
    database.prepare('DELETE FROM staff_types WHERE id = ?').run(req.params.id);
    res.json({ message: 'Staff type deleted' });
  } catch (err) {
    console.error('deleteStaffType error:', err);
    res.status(500).json({ error: err.message });
  }
};

// ══════════════════════════════════════════════════════════════════════════════
// QUALIFICATIONS MANAGEMENT
// ══════════════════════════════════════════════════════════════════════════════

// GET /api/staff/qualifications
exports.getQualifications = (req, res) => {
  try {
    const database = getDb();
    const quals = database.prepare(
      'SELECT * FROM qualifications WHERE is_active = 1 ORDER BY name'
    ).all();
    res.json(quals);
  } catch (err) {
    console.error('getQualifications error:', err);
    res.status(500).json({ error: err.message });
  }
};

// POST /api/staff/qualifications
exports.createQualification = (req, res) => {
  try {
    const database = getDb();
    const { name, description } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }
    const id = uuidv4();
    database.prepare(
      'INSERT INTO qualifications (id, name, description) VALUES (?, ?, ?)'
    ).run(id, name.trim(), description || null);

    const created = database.prepare('SELECT * FROM qualifications WHERE id = ?').get(id);
    res.status(201).json({ message: 'Qualification added', data: created });
  } catch (err) {
    if (err.message.includes('UNIQUE constraint')) {
      return res.status(400).json({ error: 'This qualification already exists' });
    }
    console.error('createQualification error:', err);
    res.status(500).json({ error: err.message });
  }
};

// PUT /api/staff/qualifications/:id
exports.updateQualification = (req, res) => {
  try {
    const database = getDb();
    const { name, description } = req.body;
    if (!name || !name.trim()) {
      return res.status(400).json({ error: 'Name is required' });
    }
    database.prepare(
      'UPDATE qualifications SET name = ?, description = ? WHERE id = ?'
    ).run(name.trim(), description || null, req.params.id);

    const updated = database.prepare('SELECT * FROM qualifications WHERE id = ?').get(req.params.id);
    res.json({ message: 'Qualification updated', data: updated });
  } catch (err) {
    if (err.message.includes('UNIQUE constraint')) {
      return res.status(400).json({ error: 'This qualification already exists' });
    }
    console.error('updateQualification error:', err);
    res.status(500).json({ error: err.message });
  }
};

// DELETE /api/staff/qualifications/:id
exports.deleteQualification = (req, res) => {
  try {
    const database = getDb();
    database.prepare('DELETE FROM qualifications WHERE id = ?').run(req.params.id);
    res.json({ message: 'Qualification deleted' });
  } catch (err) {
    console.error('deleteQualification error:', err);
    res.status(500).json({ error: err.message });
  }
};

// ──────────────────────────────────────────────────────────────────────────────
// POST /api/staff/:id/books
// ──────────────────────────────────────────────────────────────────────────────
exports.assignBooks = (req, res) => {
  try {
    const database = getDb();
    const { id } = req.params; // staff_id
    const { course_book_ids } = req.body; // array of course_books.id

    if (!Array.isArray(course_book_ids)) {
      return res.status(400).json({ error: 'course_book_ids must be an array' });
    }

    const transaction = database.transaction((staffId, bookIds) => {
      // Clear existing first
      database.prepare('DELETE FROM staff_books WHERE staff_id = ?').run(staffId);
      
      const insert = database.prepare('INSERT INTO staff_books (id, staff_id, course_book_id) VALUES (?, ?, ?)');
      for (const cb_id of bookIds) {
        insert.run(uuidv4(), staffId, cb_id);
      }
    });

    transaction(id, course_book_ids);
    res.json({ message: 'Books assigned successfully' });
  } catch (err) {
    console.error('Staff assignBooks error:', err);
    res.status(500).json({ error: err.message });
  }
};

exports.bulkDelete = (req, res) => {
  try {
    const database = getDb();
    const { staffIds } = req.body;
    if (!staffIds || !Array.isArray(staffIds) || staffIds.length === 0) {
      return res.status(400).json({ error: 'staffIds array is required' });
    }

    const deleteTransaction = database.transaction(() => {
      for (const id of staffIds) {
        // Delete documents files
        const documents = database.prepare('SELECT * FROM staff_documents WHERE staff_id = ?').all(id);
        for (const doc of documents) {
          const filePath = require('path').join(__dirname, '../../', doc.file_path);
          if (require('fs').existsSync(filePath)) {
            require('fs').unlinkSync(filePath);
          }
        }
        // Delete staff documents in DB
        database.prepare('DELETE FROM staff_documents WHERE staff_id = ?').run(id);
        // Delete staff books assignments
        database.prepare('DELETE FROM staff_books WHERE staff_id = ?').run(id);
        // Delete staff
        database.prepare('DELETE FROM staff WHERE id = ?').run(id);
      }
    });

    deleteTransaction();

    res.json({ success: true, message: `Successfully deleted ${staffIds.length} staff members` });
  } catch (err) {
    console.error('Staff bulkDelete error:', err);
    res.status(500).json({ error: err.message });
  }
};
