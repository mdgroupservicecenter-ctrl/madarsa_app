const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// ─── HOSTEL CRUD ─────────────────────────────────────────────────────

exports.getHostels = (req, res) => {
  try {
    const hostels = db.prepare(`
      SELECT h.*, 
             (SELECT COUNT(*) FROM hostel_rooms WHERE hostel_id = h.id) AS room_count,
             (SELECT COUNT(*) FROM hostel_beds b JOIN hostel_rooms r ON b.room_id = r.id WHERE r.hostel_id = h.id) AS capacity,
             (SELECT COUNT(*) FROM hostel_allocations a JOIN hostel_beds b ON a.bed_id = b.id JOIN hostel_rooms r ON b.room_id = r.id WHERE r.hostel_id = h.id AND a.status = 'Active') AS occupied_count
      FROM hostels h
      ORDER BY h.name ASC
    `).all();

    res.json(hostels);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching hostels', error: error.message });
  }
};

exports.createHostel = (req, res) => {
  try {
    const { name, description } = req.body;

    if (!name) {
      return res.status(400).json({ message: 'Hostel name is required' });
    }

    const id = uuidv4();
    db.prepare(`
      INSERT INTO hostels (id, name, description)
      VALUES (?, ?, ?)
    `).run(id, String(name).trim(), description ? description.trim() : null);

    res.status(201).json({
      success: true,
      message: 'Hostel created successfully',
      data: { id, name, description }
    });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ message: 'Hostel name already exists' });
    }
    res.status(500).json({ message: 'Error creating hostel', error: error.message });
  }
};

exports.updateHostel = (req, res) => {
  try {
    const { id } = req.params;
    const { name, description } = req.body;

    const existing = db.prepare('SELECT * FROM hostels WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Hostel not found' });
    }

    db.prepare(`
      UPDATE hostels
      SET name = COALESCE(?, name),
          description = ?
      WHERE id = ?
    `).run(name ? String(name).trim() : null, description ? description.trim() : null, id);

    const updated = db.prepare('SELECT * FROM hostels WHERE id = ?').get(id);
    res.json({
      success: true,
      message: 'Hostel updated successfully',
      data: updated
    });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ message: 'Hostel name already exists' });
    }
    res.status(500).json({ message: 'Error updating hostel', error: error.message });
  }
};

exports.deleteHostel = (req, res) => {
  try {
    const { id } = req.params;
    const existing = db.prepare('SELECT * FROM hostels WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Hostel not found' });
    }

    // Check if there are active stay records in this hostel
    const activeCount = db.prepare(`
      SELECT COUNT(*) as count 
      FROM hostel_allocations a 
      JOIN hostel_beds b ON a.bed_id = b.id
      JOIN hostel_rooms r ON b.room_id = r.id
      WHERE r.hostel_id = ? AND a.status = 'Active'
    `).get(id).count;

    if (activeCount > 0) {
      return res.status(400).json({
        message: 'Cannot delete hostel with active stay records. Vacate all students first.'
      });
    }

    db.prepare('DELETE FROM hostels WHERE id = ?').run(id);
    res.json({ success: true, message: 'Hostel deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting hostel', error: error.message });
  }
};

// ─── ROOM CRUD ───────────────────────────────────────────────────────

exports.getRooms = (req, res) => {
  try {
    const { hostel_id } = req.query;

    let queryStr = `
      SELECT r.*, 
             h.name AS hostel_name,
             (SELECT COUNT(*) FROM hostel_beds WHERE room_id = r.id) AS bed_count,
             (SELECT COUNT(*) FROM hostel_allocations a JOIN hostel_beds b ON a.bed_id = b.id WHERE b.room_id = r.id AND a.status = 'Active') AS occupied_count
      FROM hostel_rooms r
      JOIN hostels h ON r.hostel_id = h.id
      WHERE 1=1
    `;
    const params = [];

    if (hostel_id) {
      queryStr += ` AND r.hostel_id = ?`;
      params.push(hostel_id);
    }

    queryStr += ` ORDER BY r.room_number ASC`;

    const rooms = db.prepare(queryStr).all(...params);

    const result = rooms.map(room => ({
      ...room,
      vacant_count: Math.max(0, room.bed_count - room.occupied_count)
    }));

    res.json(result);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching rooms', error: error.message });
  }
};

exports.createRoom = (req, res) => {
  try {
    const { hostel_id, room_number, description } = req.body;

    if (!hostel_id || !room_number) {
      return res.status(400).json({ message: 'Hostel ID and room number are required' });
    }

    const id = uuidv4();
    db.prepare(`
      INSERT INTO hostel_rooms (id, hostel_id, room_number, description)
      VALUES (?, ?, ?, ?)
    `).run(id, hostel_id, String(room_number).trim(), description ? description.trim() : null);

    res.status(201).json({
      success: true,
      message: 'Room created successfully',
      data: { id, hostel_id, room_number, description }
    });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ message: 'Room number already exists in this hostel' });
    }
    res.status(500).json({ message: 'Error creating room', error: error.message });
  }
};

exports.updateRoom = (req, res) => {
  try {
    const { id } = req.params;
    const { room_number, description } = req.body;

    const existing = db.prepare('SELECT * FROM hostel_rooms WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Room not found' });
    }

    db.prepare(`
      UPDATE hostel_rooms
      SET room_number = COALESCE(?, room_number),
          description = ?
      WHERE id = ?
    `).run(room_number ? String(room_number).trim() : null, description ? description.trim() : null, id);

    const updated = db.prepare('SELECT * FROM hostel_rooms WHERE id = ?').get(id);
    res.json({
      success: true,
      message: 'Room updated successfully',
      data: updated
    });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ message: 'Room number already exists in this hostel' });
    }
    res.status(500).json({ message: 'Error updating room', error: error.message });
  }
};

exports.deleteRoom = (req, res) => {
  try {
    const { id } = req.params;
    const existing = db.prepare('SELECT * FROM hostel_rooms WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Room not found' });
    }

    const activeCount = db.prepare(`
      SELECT COUNT(*) as count 
      FROM hostel_allocations a 
      JOIN hostel_beds b ON a.bed_id = b.id 
      WHERE b.room_id = ? AND a.status = 'Active'
    `).get(id).count;

    if (activeCount > 0) {
      return res.status(400).json({ 
        message: 'Cannot delete room with active stay records. Vacate all students first.' 
      });
    }

    db.prepare('DELETE FROM hostel_rooms WHERE id = ?').run(id);
    res.json({ success: true, message: 'Room deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting room', error: error.message });
  }
};

// ─── BED CRUD ────────────────────────────────────────────────────────

exports.getBeds = (req, res) => {
  try {
    const { room_id } = req.query;

    if (!room_id) {
      return res.status(400).json({ message: 'Room ID is required' });
    }

    const beds = db.prepare(`
      SELECT b.*,
             r.room_number,
             (SELECT a.id FROM hostel_allocations a WHERE a.bed_id = b.id AND a.status = 'Active') AS allocation_id,
             (SELECT s.id FROM hostel_allocations a JOIN students s ON a.student_id = s.id WHERE a.bed_id = b.id AND a.status = 'Active') AS student_id,
             (SELECT s.full_name FROM hostel_allocations a JOIN students s ON a.student_id = s.id WHERE a.bed_id = b.id AND a.status = 'Active') AS student_name,
             (SELECT s.gr_no FROM hostel_allocations a JOIN students s ON a.student_id = s.id WHERE a.bed_id = b.id AND a.status = 'Active') AS student_gr_no
      FROM hostel_beds b
      JOIN hostel_rooms r ON b.room_id = r.id
      WHERE b.room_id = ?
      ORDER BY b.bed_number ASC
    `).all(room_id);

    const result = beds.map(bed => ({
      ...bed,
      is_occupied: bed.allocation_id ? 1 : 0
    }));

    res.json(result);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching beds', error: error.message });
  }
};

exports.createBed = (req, res) => {
  try {
    const { room_id, bed_number, description } = req.body;

    if (!room_id || !bed_number) {
      return res.status(400).json({ message: 'Room ID and bed number are required' });
    }

    const id = uuidv4();
    db.prepare(`
      INSERT INTO hostel_beds (id, room_id, bed_number, description)
      VALUES (?, ?, ?, ?)
    `).run(id, room_id, String(bed_number).trim(), description ? description.trim() : null);

    res.status(201).json({
      success: true,
      message: 'Bed created successfully',
      data: { id, room_id, bed_number, description }
    });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ message: 'Bed number already exists in this room' });
    }
    res.status(500).json({ message: 'Error creating bed', error: error.message });
  }
};

exports.deleteBed = (req, res) => {
  try {
    const { id } = req.params;
    const existing = db.prepare('SELECT * FROM hostel_beds WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Bed not found' });
    }

    // Check if bed is occupied
    const active = db.prepare("SELECT * FROM hostel_allocations WHERE bed_id = ? AND status = 'Active'").get(id);
    if (active) {
      return res.status(400).json({ message: 'Cannot delete an occupied bed. Vacate the student first.' });
    }

    db.prepare('DELETE FROM hostel_beds WHERE id = ?').run(id);
    res.json({ success: true, message: 'Bed deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting bed', error: error.message });
  }
};

// ─── ALLOCATIONS ─────────────────────────────────────────────────────

exports.getAllocations = (req, res) => {
  try {
    const { room_id, status, search } = req.query;

    let queryStr = `
      SELECT a.*, 
             s.full_name AS student_name, 
             s.father_name,
             s.surname,
             s.gr_no, 
             s.village,
             s.registration_number, 
             s.class_name, 
             CAST((julianday('now') - julianday(s.date_of_birth)) / 365.25 AS INTEGER) AS age,
             b.bed_number,
             r.id AS room_id,
             r.room_number,
             h.id AS hostel_id,
             h.name AS hostel_name
      FROM hostel_allocations a
      JOIN students s ON a.student_id = s.id
      JOIN hostel_beds b ON a.bed_id = b.id
      JOIN hostel_rooms r ON b.room_id = r.id
      JOIN hostels h ON r.hostel_id = h.id
      WHERE 1=1
    `;
    const params = [];

    if (room_id) {
      queryStr += ` AND r.id = ?`;
      params.push(room_id);
    }

    if (status && status !== 'All') {
      queryStr += ` AND a.status = ?`;
      params.push(status);
    }

    if (search) {
      queryStr += ` AND (s.full_name LIKE ? OR s.gr_no LIKE ? OR r.room_number LIKE ? OR h.name LIKE ?)`;
      const searchPattern = `%${search}%`;
      params.push(searchPattern, searchPattern, searchPattern, searchPattern);
    }

    queryStr += ` ORDER BY a.status ASC, a.allocation_date DESC`;

    const allocations = db.prepare(queryStr).all(...params);
    res.json(allocations);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching stay records', error: error.message });
  }
};

exports.allocateRoom = (req, res) => {
  try {
    const { bed_id, student_id, allocation_date } = req.body;

    if (!bed_id || !student_id) {
      return res.status(400).json({ message: 'Bed and Student are required' });
    }

    const allocDate = allocation_date || new Date().toISOString().split('T')[0];

    // Validate student
    const student = db.prepare('SELECT * FROM students WHERE id = ?').get(student_id);
    if (!student) return res.status(404).json({ message: 'Student not found' });
    if (student.is_active === 0) return res.status(400).json({ message: 'Student is inactive' });

    // Validate not already allocated
    const alreadyAllocated = db.prepare(`
      SELECT a.*, r.room_number, h.name AS hostel_name 
      FROM hostel_allocations a
      JOIN hostel_beds b ON a.bed_id = b.id
      JOIN hostel_rooms r ON b.room_id = r.id
      JOIN hostels h ON r.hostel_id = h.id
      WHERE a.student_id = ? AND a.status = 'Active'
    `).get(student_id);

    if (alreadyAllocated) {
      return res.status(400).json({ 
        message: `Student already allocated to ${alreadyAllocated.hostel_name} Room ${alreadyAllocated.room_number}` 
      });
    }

    // Validate bed exists and is vacant
    const bed = db.prepare('SELECT * FROM hostel_beds WHERE id = ?').get(bed_id);
    if (!bed) return res.status(404).json({ message: 'Bed not found' });

    const bedOccupied = db.prepare("SELECT * FROM hostel_allocations WHERE bed_id = ? AND status = 'Active'").get(bed_id);
    if (bedOccupied) return res.status(400).json({ message: 'Bed is already occupied' });

    const id = uuidv4();
    db.prepare(`
      INSERT INTO hostel_allocations (id, bed_id, student_id, allocation_date, status)
      VALUES (?, ?, ?, ?, 'Active')
    `).run(id, bed_id, student_id, allocDate);

    res.status(201).json({ success: true, message: 'Student allocated successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error allocating room', error: error.message });
  }
};

exports.bulkAllocateRoom = (req, res) => {
  try {
    const { room_id, student_ids, allocation_date } = req.body;

    if (!room_id || !student_ids || !Array.isArray(student_ids) || student_ids.length === 0) {
      return res.status(400).json({ message: 'Room ID and at least one student are required' });
    }

    const allocDate = allocation_date || new Date().toISOString().split('T')[0];

    // Find all vacant beds in the selected room
    const vacantBeds = db.prepare(`
      SELECT * FROM hostel_beds 
      WHERE room_id = ? 
        AND id NOT IN (SELECT bed_id FROM hostel_allocations WHERE status = 'Active')
      ORDER BY bed_number ASC
    `).all(room_id);

    if (student_ids.length > vacantBeds.length) {
      return res.status(400).json({
        message: `Cannot allocate ${student_ids.length} students. Only ${vacantBeds.length} vacant bed(s) available in this room.`
      });
    }

    const results = { allocated: [], skipped: [] };
    const getStudent = db.prepare('SELECT id, full_name, gr_no, is_active FROM students WHERE id = ?');
    const checkAllocated = db.prepare(`
      SELECT a.id, r.room_number, h.name AS hostel_name 
      FROM hostel_allocations a 
      JOIN hostel_beds b ON a.bed_id = b.id
      JOIN hostel_rooms r ON b.room_id = r.id 
      JOIN hostels h ON r.hostel_id = h.id
      WHERE a.student_id = ? AND a.status = 'Active'
    `);
    const insertAlloc = db.prepare(`
      INSERT INTO hostel_allocations (id, bed_id, student_id, allocation_date, status)
      VALUES (?, ?, ?, ?, 'Active')
    `);

    let bedIndex = 0;
    const runBulk = db.transaction(() => {
      for (const studentId of student_ids) {
        const student = getStudent.get(studentId);
        if (!student) {
          results.skipped.push({ studentId, reason: 'Student not found' });
          continue;
        }
        if (student.is_active === 0) {
          results.skipped.push({ studentId, name: student.full_name, reason: 'Student is inactive' });
          continue;
        }

        const existing = checkAllocated.get(studentId);
        if (existing) {
          results.skipped.push({
            studentId,
            name: student.full_name,
            reason: `Already allocated to ${existing.hostel_name} Room ${existing.room_number}`
          });
          continue;
        }

        // Pair with the next available vacant bed
        const bed = vacantBeds[bedIndex++];
        const id = uuidv4();
        insertAlloc.run(id, bed.id, studentId, allocDate);
        results.allocated.push({
          id,
          studentId,
          name: student.full_name,
          bedNumber: bed.bed_number
        });
      }
    });

    runBulk();

    res.status(201).json({
      success: true,
      message: `${results.allocated.length} student(s) allocated successfully`,
      data: results
    });
  } catch (error) {
    res.status(500).json({ message: 'Error in bulk allocation', error: error.message });
  }
};

exports.vacateRoom = (req, res) => {
  try {
    const { id } = req.params;
    const { vacate_date } = req.body;

    const existing = db.prepare('SELECT * FROM hostel_allocations WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Stay record not found' });
    }
    if (existing.status === 'Vacated') {
      return res.status(400).json({ message: 'Stay is already marked as Vacated' });
    }

    const vacDate = vacate_date || new Date().toISOString().split('T')[0];

    db.prepare(`
      UPDATE hostel_allocations
      SET status = 'Vacated',
          vacate_date = ?
      WHERE id = ?
    `).run(vacDate, id);

    res.json({ success: true, message: 'Student vacated successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error vacating stay record', error: error.message });
  }
};

exports.deleteAllocation = (req, res) => {
  try {
    const { id } = req.params;
    db.prepare('DELETE FROM hostel_allocations WHERE id = ?').run(id);
    res.json({ success: true, message: 'Stay record deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting stay record', error: error.message });
  }
};
