const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// --- Departments ---
exports.getAllDepartments = (req, res) => {
  try {
    const departments = db.prepare(`
      SELECT d.*,
             p.name as parent_name,
             COUNT(DISTINCT c.id) as class_count,
             GROUP_CONCAT(DISTINCT c.name || '||' || c.id) as classes_raw
      FROM departments d
      LEFT JOIN departments p ON d.parent_id = p.id
      LEFT JOIN classes c ON c.department_id = d.id AND c.is_active = 1
      WHERE d.is_active = 1
      GROUP BY d.id
      ORDER BY d.created_at DESC
    `).all();

    // Fetch all sub-departments with their class counts
    const subDeptsAll = db.prepare(`
      SELECT s.*,
             p.name as parent_name,
             COUNT(DISTINCT c.id) as class_count,
             GROUP_CONCAT(DISTINCT c.name || '||' || c.id) as classes_raw
      FROM departments s
      LEFT JOIN departments p ON s.parent_id = p.id
      LEFT JOIN classes c ON c.department_id = s.id AND c.is_active = 1
      WHERE s.parent_id IS NOT NULL AND s.is_active = 1
      GROUP BY s.id
      ORDER BY s.created_at ASC
    `).all();

    for (const sub of subDeptsAll) {
      if (sub.classes_raw) {
        const items = sub.classes_raw.split(',');
        sub.classes = items.map(item => {
          const parts = item.split('||');
          return { name: parts[0], id: parts[1] };
        });
      } else {
        sub.classes = [];
      }
      delete sub.classes_raw;
    }

    for (const dept of departments) {
      if (dept.classes_raw) {
        const items = dept.classes_raw.split(',');
        dept.classes = items.map(item => {
          const parts = item.split('||');
          return { name: parts[0], id: parts[1] };
        });
      } else {
        dept.classes = [];
      }
      delete dept.classes_raw;

      dept.sub_departments = subDeptsAll.filter(s => s.parent_id === dept.id);
      dept.sub_department_count = dept.sub_departments.length;
    }

    res.json(departments);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createDepartment = (req, res) => {
  try {
    const { name, description, head_name, parent_id } = req.body;
    if (!name) return res.status(400).json({ error: 'Name is required' });

    const id = uuidv4();
    const insert = db.prepare('INSERT INTO departments (id, name, description, head_name, parent_id) VALUES (?, ?, ?, ?, ?)');
    insert.run(id, name, description || null, head_name || null, parent_id || null);
    
    res.status(201).json({ id, name, description, head_name, parent_id });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Department name already exists' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.updateDepartment = (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, head_name, parent_id, is_active } = req.body;
    let updates = [];
    let values = [];

    if (name !== undefined) { updates.push('name = ?'); values.push(name); }
    if (description !== undefined) { updates.push('description = ?'); values.push(description); }
    if (head_name !== undefined) { updates.push('head_name = ?'); values.push(head_name); }
    if (parent_id !== undefined) { updates.push('parent_id = ?'); values.push(parent_id || null); }
    if (is_active !== undefined) { updates.push('is_active = ?'); values.push(is_active ? 1 : 0); }

    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    
    values.push(id);
    const info = db.prepare(`UPDATE departments SET ${updates.join(', ')} WHERE id = ?`).run(...values);
    if (info.changes === 0) return res.status(404).json({ error: 'Department not found' });
    
    res.json({ message: 'Department updated successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteDepartment = (req, res) => {
  try {
    const { id } = req.params;
    db.prepare('UPDATE departments SET parent_id = NULL WHERE parent_id = ?').run(id);
    const info = db.prepare('DELETE FROM departments WHERE id = ?').run(id);
    if (info.changes === 0) return res.status(404).json({ error: 'Department not found' });
    res.json({ message: 'Department deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// --- Courses ---
exports.getAllCourses = (req, res) => {
  try {
    const courses = db.prepare('SELECT * FROM courses WHERE is_active = 1 ORDER BY created_at DESC').all();
    res.json(courses);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createCourse = (req, res) => {
  try {
    const { name, description } = req.body;
    if (!name) return res.status(400).json({ error: 'Name is required' });

    const id = uuidv4();
    const insert = db.prepare('INSERT INTO courses (id, name, description) VALUES (?, ?, ?)');
    insert.run(id, name, description);
    
    res.status(201).json({ id, name, description });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Course name already exists' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.updateCourse = (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, is_active } = req.body;
    let updates = [];
    let values = [];

    if (name !== undefined) { updates.push('name = ?'); values.push(name); }
    if (description !== undefined) { updates.push('description = ?'); values.push(description); }
    if (is_active !== undefined) { updates.push('is_active = ?'); values.push(is_active ? 1 : 0); }

    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    
    values.push(id);
    const info = db.prepare(`UPDATE courses SET ${updates.join(', ')} WHERE id = ?`).run(...values);
    if (info.changes === 0) return res.status(404).json({ error: 'Course not found' });
    
    res.json({ message: 'Course updated successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteCourse = (req, res) => {
  try {
    const { id } = req.params;
    const info = db.prepare('DELETE FROM courses WHERE id = ?').run(id);
    if (info.changes === 0) return res.status(404).json({ error: 'Course not found' });
    res.json({ message: 'Course deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// --- Books ---
exports.getAllBooks = (req, res) => {
  try {
    const books = db.prepare('SELECT * FROM books WHERE is_active = 1 ORDER BY created_at DESC').all();
    res.json(books);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createBook = (req, res) => {
  try {
    const { name, description, author, category } = req.body;
    if (!name) return res.status(400).json({ error: 'Name is required' });

    const id = uuidv4();
    const insert = db.prepare('INSERT INTO books (id, name, description, author, category) VALUES (?, ?, ?, ?, ?)');
    insert.run(id, name, description, author, category);
    
    res.status(201).json({ id, name, description, author, category });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Book name already exists' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.updateBook = (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, author, category, is_active } = req.body;
    let updates = [];
    let values = [];

    if (name !== undefined) { updates.push('name = ?'); values.push(name); }
    if (description !== undefined) { updates.push('description = ?'); values.push(description); }
    if (author !== undefined) { updates.push('author = ?'); values.push(author); }
    if (category !== undefined) { updates.push('category = ?'); values.push(category); }
    if (is_active !== undefined) { updates.push('is_active = ?'); values.push(is_active ? 1 : 0); }

    if (updates.length === 0) return res.status(400).json({ error: 'No fields to update' });
    
    values.push(id);
    const info = db.prepare(`UPDATE books SET ${updates.join(', ')} WHERE id = ?`).run(...values);
    if (info.changes === 0) return res.status(404).json({ error: 'Book not found' });
    
    res.json({ message: 'Book updated successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteBook = (req, res) => {
  try {
    const { id } = req.params;
    const info = db.prepare('DELETE FROM books WHERE id = ?').run(id);
    if (info.changes === 0) return res.status(404).json({ error: 'Book not found' });
    res.json({ message: 'Book deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// --- Mappings (Hierarchy) ---

// Assign Course to Class
exports.assignCourseToClass = (req, res) => {
  try {
    const { class_id, course_id } = req.body;
    const id = uuidv4();
    db.prepare('INSERT INTO class_courses (id, class_id, course_id) VALUES (?, ?, ?)')
      .run(id, class_id, course_id);
    res.status(201).json({ message: 'Course assigned to class', class_course_id: id });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Course is already assigned to this class' });
    }
    res.status(500).json({ error: error.message });
  }
};

// Remove Course from Class
exports.removeCourseFromClass = (req, res) => {
  try {
    const { id } = req.params; // class_course_id
    db.prepare('DELETE FROM class_courses WHERE id = ?').run(id);
    res.json({ message: 'Course mapping removed' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// Assign Book to specific Course within a Class
exports.assignBookToClassCourse = (req, res) => {
  try {
    const { class_course_id, book_id } = req.body;
    if (!class_course_id || !book_id) {
      return res.status(400).json({ error: 'class_course_id and book_id are required' });
    }

    // Check if already assigned to this division
    const existing = db.prepare('SELECT id FROM course_books WHERE class_course_id = ? AND book_id = ?').get(class_course_id, book_id);
    if (existing) {
      return res.json({ message: 'Book is already assigned to this division', course_book_id: existing.id });
    }

    const id = uuidv4();
    db.prepare('INSERT INTO course_books (id, class_course_id, book_id) VALUES (?, ?, ?)').run(id, class_course_id, book_id);

    res.status(201).json({
      message: 'Book assigned to division successfully',
      course_book_id: id,
    });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Book is already assigned to this class-course' });
    }
    res.status(500).json({ error: error.message });
  }
};

// Remove Book from specific Course within a Class
exports.removeBookFromClassCourse = (req, res) => {
  try {
    const { id } = req.params; // course_book_id
    db.prepare('DELETE FROM course_books WHERE id = ?').run(id);
    res.json({ message: 'Book mapping removed' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// --- Full Hierarchy Query ---

exports.getAcademicHierarchy = (req, res) => {
  try {
    const classes = db.prepare(`
      SELECT c.id, c.name, c.description, c.duration, c.department_id, 
             d.name as department_name,
             d.parent_id as department_parent_id,
             p.name as parent_department_name
      FROM classes c
      LEFT JOIN departments d ON c.department_id = d.id
      LEFT JOIN departments p ON d.parent_id = p.id
      WHERE c.is_active = 1
      ORDER BY c.name
    `).all();
    
    const classCoursesRaw = db.prepare(`
      SELECT cc.id as class_course_id, cc.class_id, c.id as course_id, c.name, c.description
      FROM class_courses cc
      JOIN courses c ON cc.course_id = c.id
      WHERE c.is_active = 1
    `).all();

    const courseBooksRaw = db.prepare(`
      SELECT cb.id as course_book_id, cb.class_course_id, b.id as book_id, b.name, b.author, b.category
      FROM course_books cb
      JOIN books b ON cb.book_id = b.id
      WHERE b.is_active = 1
    `).all();

    // Get teacher assignments: staff_books links staff to course_books
    const staffBooksRaw = db.prepare(`
      SELECT sb.course_book_id, s.full_name as teacher_name, s.id as teacher_id
      FROM staff_books sb
      JOIN staff s ON sb.staff_id = s.id
      WHERE s.is_active = 1
    `).all();

    // Map teacher to course_book_id
    const teacherMap = {};
    for (const sb of staffBooksRaw) {
      teacherMap[sb.course_book_id] = { teacher_name: sb.teacher_name, teacher_id: sb.teacher_id };
    }

    // Map courseBooks to classCourses
    const ccMap = {};
    for (const cc of classCoursesRaw) {
      cc.books = [];
      ccMap[cc.class_course_id] = cc;
    }
    for (const b of courseBooksRaw) {
      if (ccMap[b.class_course_id]) {
        // Attach teacher info to each book
        b.teacher_name = teacherMap[b.course_book_id]?.teacher_name || '';
        b.teacher_id = teacherMap[b.course_book_id]?.teacher_id || '';
        ccMap[b.class_course_id].books.push(b);
      }
    }

    // Map classCourses to classes
    const classMap = {};
    for (const cl of classes) {
      cl.courses = [];
      classMap[cl.id] = cl;
    }
    for (const cc of classCoursesRaw) {
      if (classMap[cc.class_id]) {
        classMap[cc.class_id].courses.push(cc);
      }
    }

    res.json(classes);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// --- Class Book Periods ---
exports.getClassBookPeriods = (req, res) => {
  try {
    const { class_id } = req.query;
    
    let query = `
      SELECT cbp.*, b.name as book_name, b.author as book_author
      FROM class_book_periods cbp
      LEFT JOIN books b ON cbp.book_id = b.id
    `;
    const params = [];
    if (class_id) {
      query += ' WHERE cbp.class_id = ?';
      params.push(class_id);
    }
    query += ' ORDER BY cbp.period_number ASC';
    
    const periods = db.prepare(query).all(...params);

    // Get teacher info for each book in the class via staff_books → course_books → class_courses
    if (class_id) {
      const teacherInfo = db.prepare(`
        SELECT b.id as book_id, s.full_name as teacher_name
        FROM staff_books sb
        JOIN staff s ON sb.staff_id = s.id
        JOIN course_books cb ON sb.course_book_id = cb.id
        JOIN books b ON cb.book_id = b.id
        JOIN class_courses cc ON cb.class_course_id = cc.id
        WHERE cc.class_id = ? AND s.is_active = 1
      `).all(class_id);

      const teacherMap = {};
      for (const t of teacherInfo) {
        teacherMap[t.book_id] = t.teacher_name;
      }

      for (const p of periods) {
        p.teacher_name = teacherMap[p.book_id] || '';
      }
    }

    res.json(periods);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.saveClassBookPeriod = (req, res) => {
  try {
    const { class_id, book_id, period_number, start_time, end_time } = req.body;
    if (!class_id || !book_id || period_number === undefined || !start_time || !end_time) {
      return res.status(400).json({ error: 'Class, book, period number, start and end times are required' });
    }
    const id = uuidv4();
    db.prepare(`
      INSERT INTO class_book_periods (id, class_id, book_id, period_number, start_time, end_time)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(class_id, book_id, period_number) DO UPDATE SET
        start_time = excluded.start_time,
        end_time = excluded.end_time
    `).run(id, class_id, book_id, parseInt(period_number, 10), start_time, end_time);
    res.json({ success: true, message: 'Class period saved successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.deleteClassBookPeriod = (req, res) => {
  try {
    const { id } = req.params;
    db.prepare('DELETE FROM class_book_periods WHERE id = ?').run(id);
    res.json({ success: true, message: 'Period deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

