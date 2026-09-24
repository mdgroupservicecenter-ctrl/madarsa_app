const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// ==============================
// 1. Exams CRUD
// ==============================

exports.getAllExams = (req, res) => {
  try {
    const exams = db.prepare('SELECT * FROM exams ORDER BY created_at DESC').all();
    res.json({ success: true, data: exams });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.createExam = (req, res) => {
  try {
    const { name, start_date, end_date, status } = req.body;
    const id = uuidv4();
    db.prepare('INSERT INTO exams (id, name, start_date, end_date, status) VALUES (?, ?, ?, ?, ?)').run(id, name, start_date, end_date, status || 'DRAFT');
    res.json({ success: true, data: { id, name, start_date, end_date } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.updateExam = (req, res) => {
  try {
    const { id } = req.params;
    const { name, start_date, end_date, status } = req.body;
    db.prepare('UPDATE exams SET name=?, start_date=?, end_date=?, status=? WHERE id=?').run(name, start_date, end_date, status, id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.deleteExam = (req, res) => {
  try {
    db.prepare('DELETE FROM exams WHERE id=?').run(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// ==============================
// 2. Exam Schedules (Mappings)
// ==============================

exports.getExamSchedules = (req, res) => {
  try {
    const { exam_id } = req.params;
    const schedules = db.prepare(`
      SELECT es.*, c.name as class_name, b.name as book_name,
             c.department_id,
             d.name as department_name,
             d.parent_id as department_parent_id,
             p.name as parent_department_name
      FROM exam_schedules es
      JOIN classes c ON es.class_id = c.id
      JOIN books b ON es.book_id = b.id
      LEFT JOIN departments d ON c.department_id = d.id
      LEFT JOIN departments p ON d.parent_id = p.id
      WHERE es.exam_id = ?
    `).all(exam_id);
    res.json({ success: true, data: schedules });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.createExamSchedule = (req, res) => {
  try {
    const { exam_id, class_id, book_id, exam_date, start_time, end_time, max_marks, passing_marks } = req.body;
    const id = uuidv4();
    db.prepare(`INSERT INTO exam_schedules (id, exam_id, class_id, book_id, exam_date, start_time, end_time, max_marks, passing_marks) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(id, exam_id, class_id, book_id, exam_date, start_time, end_time, max_marks, passing_marks);
    res.json({ success: true, data: { id } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.updateExamSchedule = (req, res) => {
  try {
    const { id } = req.params;
    const { class_id, book_id, exam_date, start_time, end_time, max_marks, passing_marks } = req.body;
    db.prepare(`UPDATE exam_schedules SET class_id=?, book_id=?, exam_date=?, start_time=?, end_time=?, max_marks=?, passing_marks=? WHERE id=?`).run(class_id, book_id, exam_date, start_time, end_time, max_marks, passing_marks, id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.deleteExamSchedule = (req, res) => {
  try {
    db.prepare('DELETE FROM exam_schedules WHERE id=?').run(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// ==============================
// 3. Exam Halls CRUD
// ==============================

exports.getAllHalls = (req, res) => {
  try {
    const halls = db.prepare('SELECT * FROM exam_halls').all();
    res.json({ success: true, data: halls });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.createHall = (req, res) => {
  try {
    const { name, total_rows, total_columns } = req.body;
    const capacity = total_rows * total_columns;
    const id = uuidv4();
    db.prepare('INSERT INTO exam_halls (id, name, total_rows, total_columns, total_capacity) VALUES (?, ?, ?, ?, ?)').run(id, name, total_rows, total_columns, capacity);
    res.json({ success: true, data: { id, name, total_rows, total_columns, total_capacity: capacity } });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.updateHall = (req, res) => {
  try {
    const { id } = req.params;
    const { name, total_rows, total_columns } = req.body;
    const capacity = total_rows * total_columns;
    db.prepare('UPDATE exam_halls SET name=?, total_rows=?, total_columns=?, total_capacity=? WHERE id=?').run(name, total_rows, total_columns, capacity, id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.deleteHall = (req, res) => {
  try {
    db.prepare('DELETE FROM exam_halls WHERE id=?').run(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

// ==============================
// 5. Exam Results CRUD
// ==============================

exports.getResults = (req, res) => {
  try {
    const { exam_id } = req.params;
    const results = db.prepare(`
      SELECT er.*, s.full_name, s.gr_no, s.class_name, b.name as book_name,
             s.department_id,
             d.name as department_name,
             d.parent_id as department_parent_id,
             p.name as parent_department_name
      FROM exam_results er
      JOIN students s ON er.student_id = s.id
      JOIN books b ON er.book_id = b.id
      LEFT JOIN departments d ON s.department_id = d.id
      LEFT JOIN departments p ON d.parent_id = p.id
      WHERE er.exam_id = ?
      ORDER BY s.class_name, s.full_name
    `).all(exam_id);
    res.json({ success: true, data: results });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.saveResult = (req, res) => {
  try {
    const { exam_id, student_id, book_id, marks_obtained, max_marks, passing_marks, remarks } = req.body;
    const grade = calcGrade(marks_obtained, max_marks);
    const id = uuidv4();
    db.prepare(`
      INSERT INTO exam_results (id, exam_id, student_id, book_id, marks_obtained, max_marks, passing_marks, grade, remarks)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(exam_id, student_id, book_id) DO UPDATE SET
        marks_obtained=excluded.marks_obtained, max_marks=excluded.max_marks,
        passing_marks=excluded.passing_marks, grade=excluded.grade,
        remarks=excluded.remarks, updated_at=datetime('now')
    `).run(id, exam_id, student_id, book_id, marks_obtained, max_marks, passing_marks, grade, remarks);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.updateResult = (req, res) => {
  try {
    const { id } = req.params;
    const { marks_obtained, max_marks, passing_marks, remarks } = req.body;
    const grade = calcGrade(marks_obtained, max_marks);
    db.prepare(`UPDATE exam_results SET marks_obtained=?, max_marks=?, passing_marks=?, grade=?, remarks=?, updated_at=datetime('now') WHERE id=?`).run(marks_obtained, max_marks, passing_marks, grade, remarks, id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.deleteResult = (req, res) => {
  try {
    db.prepare('DELETE FROM exam_results WHERE id=?').run(req.params.id);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

function calcGrade(marks, max) {
  const pct = (marks / max) * 100;
  if (pct >= 90) return 'A+';
  if (pct >= 80) return 'A';
  if (pct >= 70) return 'B+';
  if (pct >= 60) return 'B';
  if (pct >= 50) return 'C';
  if (pct >= 40) return 'D';
  return 'F';
}

// ==============================
// 4. SEATING ALGORITHM (The Blueprint Constraint)
// ==============================

exports.generateSeating = (req, res) => {
  try {
    const { exam_id, session_date, session_time, hall_ids, class_ids, book_ids } = req.body;

    // 1. Determine all schedules hitting this exact session chunk
    let sessionSchedules = db.prepare(`
      SELECT es.book_id, es.class_id, b.name as book_name, c.name as class_name
      FROM exam_schedules es
      JOIN books b ON es.book_id = b.id
      JOIN classes c ON es.class_id = c.id
      WHERE es.exam_id = ? AND TRIM(es.exam_date) = ? AND TRIM(es.start_time) LIKE ?
    `).all(exam_id, session_date.trim(), session_time.trim() + '%');

    if (class_ids && Array.isArray(class_ids) && class_ids.length > 0) {
      sessionSchedules = sessionSchedules.filter(s => class_ids.includes(s.class_id));
    }
    if (book_ids && Array.isArray(book_ids) && book_ids.length > 0) {
      sessionSchedules = sessionSchedules.filter(s => book_ids.includes(s.book_id));
    }

    if (sessionSchedules.length === 0) {
      return res.status(400).json({ success: false, message: "No subjects scheduled matching selected filters for this session." });
    }

    // 2. Fetch all matching active students assigned to these classes
    const classNames = sessionSchedules.map(s => s.class_name);
    const placeholders = classNames.map(() => '?').join(',');
    
    // NOTE: In a real app we would ensure the student is enrolled in that specific book. 
    // Here we assume if they are in the class, they take the class's scheduled book.
    const eligibleStudents = db.prepare(`
      SELECT id as student_id, full_name, class_name, category, roll_number, gr_no
      FROM students 
      WHERE is_active = 1 AND class_name IN (${placeholders})
    `).all(...classNames);

    // Roll number extraction helper
    const getRollNum = (s) => {
      if (s && s.roll_number != null && String(s.roll_number).trim() !== '') {
        const p = parseInt(String(s.roll_number).replace(/\D/g, ''), 10);
        if (!isNaN(p)) return p;
      }
      if (s && s.gr_no != null && String(s.gr_no).trim() !== '') {
        const p = parseInt(String(s.gr_no).replace(/\D/g, ''), 10);
        if (!isNaN(p)) return p;
      }
      return 999999;
    };

    // Group students by the book they are taking
    let groups = {}; 
    const studentToBookMap = {};

    eligibleStudents.forEach(stu => {
      const schedule = sessionSchedules.find(s => s.class_name === stu.class_name);
      if (schedule) {
        if (!groups[schedule.book_id]) {
          groups[schedule.book_id] = { book_id: schedule.book_id, students: [] };
        }
        groups[schedule.book_id].students.push(stu);
        studentToBookMap[stu.student_id] = schedule.book_id;
      }
    });

    // Sort students within each group by Roll Number and apply Front-Back Interleaving
    // (Roll 1, Roll N, Roll 2, Roll N-1...) so Roll 1 sits next to the LAST Roll Number!
    Object.values(groups).forEach(g => {
      g.students.sort((a, b) => getRollNum(a) - getRollNum(b));
      const sorted = g.students;
      const interleaved = [];
      let l = 0;
      let r = sorted.length - 1;
      while (l <= r) {
        if (l === r) {
          interleaved.push(sorted[l]);
          break;
        }
        interleaved.push(sorted[l]);
        interleaved.push(sorted[r]);
        l++;
        r--;
      }
      g.students = interleaved;
    });

    let queue = Object.values(groups).sort((a, b) => b.students.length - a.students.length);

    // 3. Fetch Halls and Setup Grid spaces
    const placeholdersHalls = hall_ids.map(() => '?').join(',');
    const halls = db.prepare(`SELECT * FROM exam_halls WHERE id IN (${placeholdersHalls})`).all(...hall_ids);
    
    let totalCapacity = 0;
    halls.forEach(h => totalCapacity += (h.total_rows * h.total_columns));

    if (eligibleStudents.length > totalCapacity) {
      return res.status(400).json({ success: false, message: "Total students exceed total hall capacity." });
    }

    // Prepare grid outputs and db inserts
    let placements = []; // { student_id, book_id, hall_id, r, c, seq }
    let unplacedStudents = [];

    // Prior History Map for easy lookup logic:
    const historyData = db.prepare(`SELECT student_id, book_id, seat_number FROM seating_arrangements`).all();
    const historyMap = {};
    historyData.forEach(h => {
      const key = `${h.student_id}_${h.book_id}`;
      if (!historyMap[key]) historyMap[key] = new Set();
      historyMap[key].add(h.seat_number);
    });

    // Anti-adjacency helper checking book and roll number difference (Same-class & Cross-class)
    const isConflict = (r, c, candidateBook, candidateStudent, grid) => {
      const rows = grid.length;
      const cols = grid[0].length;
      const dirs = [
        [-1, 0], [1, 0], [0, -1], [0, 1],
        [-1, -1], [-1, 1], [1, -1], [1, 1]
      ];
      const candRoll = getRollNum(candidateStudent);

      for (const [dr, dc] of dirs) {
        const nr = r + dr;
        const nc = c + dc;
        if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
          const neighborCell = grid[nr][nc];
          if (neighborCell && neighborCell.student) {
            // 1. Same Book conflict (no 2 students taking same book next to each other)
            if (neighborCell.book_id === candidateBook) return true;

            const neighborRoll = getRollNum(neighborCell.student);

            // 2. Same Class Roll Number conflict: (|roll1 - roll2| <= 2)
            if (neighborCell.student.class_name === candidateStudent.class_name) {
              if (Math.abs(candRoll - neighborRoll) <= 2) return true;
            } else {
              // 3. Cross-Class Roll Number conflict:
              // Do NOT place Roll 1/2/3 of Class A next to Roll 1/2/3 of Class B/C (top, bottom, left, right, diagonal)
              if (candRoll <= 3 && neighborRoll <= 3) {
                if (Math.abs(candRoll - neighborRoll) <= 2) return true;
              } else if (Math.abs(candRoll - neighborRoll) <= 1) {
                return true;
              }
            }
          }
        }
      }
      return false;
    };

    // We process Hall by Hall
    for (const hall of halls) {
      const rows = hall.total_rows;
      const cols = hall.total_columns;
      const grid = Array.from({ length: rows }, () => Array(cols).fill(null));

      let seatSeq = 1;
      
      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          
          if (queue.length === 0 || queue[0].students.length === 0) {
            break;
          }

          let assigned = false;

          // Attempt to assign a group according to anti-adjacency (book + roll number)
          for (let i = 0; i < queue.length; i++) {
            const group = queue[i];
            if (group.students.length === 0) continue;
            
            const candidateBook = group.book_id;

            // Try to find a student passing anti-adjacency AND seat history
            let selectedStuIndex = -1;
            
            for (let sIdx = 0; sIdx < group.students.length; sIdx++) {
              const stuCheck = group.students[sIdx];
              if (!isConflict(r, c, candidateBook, stuCheck, grid)) {
                const histKey = `${stuCheck.student_id}_${candidateBook}`;
                if (!historyMap[histKey] || !historyMap[histKey].has(seatSeq)) {
                  selectedStuIndex = sIdx;
                  break;
                }
              }
            }

            // Fallback: If history failed, pick first student who passes anti-adjacency
            if (selectedStuIndex === -1) {
              for (let sIdx = 0; sIdx < group.students.length; sIdx++) {
                const stuCheck = group.students[sIdx];
                if (!isConflict(r, c, candidateBook, stuCheck, grid)) {
                  selectedStuIndex = sIdx;
                  break;
                }
              }
            }

            if (selectedStuIndex !== -1) {
              const selectedStudent = group.students.splice(selectedStuIndex, 1)[0];
              grid[r][c] = { student: selectedStudent, book_id: candidateBook };
              
              const scheduleInfo = sessionSchedules.find(s => s.book_id === candidateBook && s.class_name === selectedStudent.class_name);

              placements.push({
                exam_id,
                hall_id: hall.id,
                student_id: selectedStudent.student_id,
                student_name: selectedStudent.full_name,
                full_name: selectedStudent.full_name,
                registration_number: selectedStudent.gr_no || selectedStudent.registration_number || '',
                roll_number: selectedStudent.roll_number != null ? String(selectedStudent.roll_number) : null,
                class_name: selectedStudent.class_name,
                book_id: candidateBook,
                book_name: scheduleInfo ? scheduleInfo.book_name : candidateBook,
                seat_row: r,
                seat_column: c,
                seat_number: seatSeq,
                session_date,
                session_time
              });

              assigned = true;
              queue.sort((a, b) => b.students.length - a.students.length);
              break; 
            }
          }

          // If no student passes strict anti-adjacency, pick student with max roll distance
          if (!assigned) {
            let bestGroupIdx = -1;
            let bestStuIdx = -1;
            let maxMinDiff = -1;

            for (let gIdx = 0; gIdx < queue.length; gIdx++) {
              const group = queue[gIdx];
              if (group.students.length === 0) continue;

              for (let sIdx = 0; sIdx < group.students.length; sIdx++) {
                const stu = group.students[sIdx];
                const candRoll = getRollNum(stu);
                let minDiff = 9999;
                const dirs = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [-1, 1], [1, -1], [1, 1]];

                for (const [dr, dc] of dirs) {
                  const nr = r + dr;
                  const nc = c + dc;
                  if (nr >= 0 && nr < rows && nc >= 0 && nc < cols) {
                    const nbr = grid[nr][nc];
                    if (nbr && nbr.student && nbr.student.class_name === stu.class_name) {
                      const diff = Math.abs(candRoll - getRollNum(nbr.student));
                      if (diff < minDiff) minDiff = diff;
                    }
                  }
                }

                if (minDiff > maxMinDiff) {
                  maxMinDiff = minDiff;
                  bestGroupIdx = gIdx;
                  bestStuIdx = sIdx;
                }
              }
            }

            if (bestGroupIdx !== -1 && bestStuIdx !== -1) {
              const selectedGroup = queue[bestGroupIdx];
              const selectedStudent = selectedGroup.students.splice(bestStuIdx, 1)[0];
              grid[r][c] = { student: selectedStudent, book_id: selectedGroup.book_id };
              
              const scheduleInfo = sessionSchedules.find(s => s.book_id === selectedGroup.book_id && s.class_name === selectedStudent.class_name);

              placements.push({
                exam_id,
                hall_id: hall.id,
                student_id: selectedStudent.student_id,
                student_name: selectedStudent.full_name,
                full_name: selectedStudent.full_name,
                registration_number: selectedStudent.gr_no || selectedStudent.registration_number || '',
                roll_number: selectedStudent.roll_number != null ? String(selectedStudent.roll_number) : null,
                class_name: selectedStudent.class_name,
                book_id: selectedGroup.book_id,
                book_name: scheduleInfo ? scheduleInfo.book_name : selectedGroup.book_id,
                seat_row: r,
                seat_column: c,
                seat_number: seatSeq,
                session_date,
                session_time
              });

              queue.sort((a, b) => b.students.length - a.students.length);
            }
          }
          seatSeq++;
        }
      }
    }

    // Optional: Identify unplaced if halls weren't enough and warn 
    unplacedStudents = queue.reduce((acc, curr) => acc.concat(curr.students), []);

    // Clean previous generation for this specific exam, date, time and selected books
    if (sessionSchedules.length > 0) {
      const bookIds = sessionSchedules.map(s => s.book_id);
      const bookPlaceholders = bookIds.map(() => '?').join(',');
      db.prepare(`
        DELETE FROM seating_arrangements 
        WHERE exam_id = ? 
          AND TRIM(session_date) = ? 
          AND TRIM(session_time) = ?
          AND book_id IN (${bookPlaceholders})
      `).run(exam_id, session_date.trim(), session_time.trim(), ...bookIds);
    }

    // Save to DB via Transaction
    const insertSeat = db.prepare(`
      INSERT OR REPLACE INTO seating_arrangements
      (id, exam_id, hall_id, student_id, book_id, seat_row, seat_column, seat_number, session_date, session_time)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    const saveTx = db.transaction((places) => {
      for (const p of places) {
        insertSeat.run(uuidv4(), p.exam_id, p.hall_id, p.student_id, p.book_id, p.seat_row, p.seat_column, p.seat_number, p.session_date, p.session_time);
      }
    });

    saveTx(placements);

    res.json({ 
      success: true, 
      message: "Seating generated.",
      data: {
        total_placed: placements.length,
        unplaced_count: unplacedStudents.length,
        placements: placements // UI can use this to draw grids
      }
    });

  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};

exports.getSeatingArrangements = (req, res) => {
  try {
    const { exam_id } = req.params;
    const seats = db.prepare(`
      SELECT sa.*, s.full_name, s.registration_number, s.roll_number, s.class_name, b.name as book_name, h.name as hall_name
      FROM seating_arrangements sa
      JOIN students s ON sa.student_id = s.id
      JOIN books b ON sa.book_id = b.id
      JOIN exam_halls h ON sa.hall_id = h.id
      WHERE sa.exam_id = ?
    `).all(exam_id);
    res.json({ success: true, data: seats });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
};
