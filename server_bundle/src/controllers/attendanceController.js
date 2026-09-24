const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// ─── Helper: Get active shift for current time ────────────────────────
function getActiveShift(now) {
  const shifts = db.prepare('SELECT * FROM madarsa_shifts WHERE is_active = 1 ORDER BY sort_order ASC').all();
  if (shifts.length === 0) return null;

  const currentTotal = now.getHours() * 60 + now.getMinutes();

  // Find the shift whose time range contains the current time
  for (const shift of shifts) {
    const [sh, sm] = shift.start_time.split(':').map(Number);
    const [eh, em] = shift.end_time.split(':').map(Number);
    const shiftStart = sh * 60 + sm;
    const shiftEnd = eh * 60 + em;
    const isWithin = shiftStart <= shiftEnd
      ? (currentTotal >= shiftStart && currentTotal <= shiftEnd)
      : (currentTotal >= shiftStart || currentTotal <= shiftEnd);
    if (isWithin) {
      return shift;
    }
  }

  // If not within any shift, return the nearest upcoming or the last one
  return shifts[shifts.length - 1];
}

// ─── Helper: Get latest shift end time for auto-absent logic ──────────
function getLatestShiftEndMinutes() {
  const shifts = db.prepare('SELECT end_time FROM madarsa_shifts WHERE is_active = 1 ORDER BY sort_order DESC LIMIT 1').all();
  if (shifts.length === 0) {
    // Fallback to old settings
    const val = db.prepare('SELECT value FROM settings WHERE key = ?').get('madarsa_close_time')?.value || '17:00';
    const [h, m] = val.split(':').map(Number);
    return h * 60 + m;
  }
  // Find the maximum end_time across all shifts
  const allShifts = db.prepare('SELECT end_time FROM madarsa_shifts WHERE is_active = 1').all();
  let maxEnd = 0;
  for (const s of allShifts) {
    const [h, m] = s.end_time.split(':').map(Number);
    maxEnd = Math.max(maxEnd, h * 60 + m);
  }
  return maxEnd;
}

// ─── Helper: Format current time as HH:MM:SS AM/PM ───────────────────
function formatTime(now) {
  let hours = now.getHours();
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const seconds = String(now.getSeconds()).padStart(2, '0');
  const ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12;
  hours = hours ? hours : 12;
  return `${String(hours).padStart(2, '0')}:${minutes}:${seconds} ${ampm}`;
}

// ─── Helper: Format current date as DD/MM/YYYY ────────────────────────
function formatDate(now) {
  const day = String(now.getDate()).padStart(2, '0');
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const year = now.getFullYear();
  return `${day}/${month}/${year}`;
}

// ─── Helper: Get local date YYYY-MM-DD in local timezone ──────────────
function getLocalDateString() {
  const localNow = new Date();
  const offset = localNow.getTimezoneOffset();
  const localDate = new Date(localNow.getTime() - (offset * 60 * 1000));
  return localDate.toISOString().split('T')[0];
}

// ═══════════════════════════════════════════════════════════════════════
// GET STUDENT ATTENDANCE
// ═══════════════════════════════════════════════════════════════════════
exports.getStudentAttendance = (req, res) => {
  try {
    const { class_name, date, shift_id } = req.query;
    if (!date) {
      return res.status(400).json({ error: 'Date is required' });
    }

    const isAll = !class_name || class_name === 'ALL' || class_name === 'All Classes';

    const students = isAll
      ? db.prepare(`
          SELECT id, registration_number, gr_no, full_name, class_name, photo_path, face_data, fingerprint_data
          FROM students
          WHERE is_active = 1
          ORDER BY full_name ASC
        `).all()
      : db.prepare(`
          SELECT id, registration_number, gr_no, full_name, class_name, photo_path, face_data, fingerprint_data
          FROM students
          WHERE class_name = ? AND is_active = 1
          ORDER BY full_name ASC
        `).all(class_name);

    let query = isAll
      ? `
        SELECT a.student_id, a.status, a.remarks, a.check_in_time, a.check_out_time, a.verification_method, a.shift_id, a.shift_name
        FROM attendance a
        WHERE a.date = ?
      `
      : `
        SELECT a.student_id, a.status, a.remarks, a.check_in_time, a.check_out_time, a.verification_method, a.shift_id, a.shift_name
        FROM attendance a
        JOIN students s ON a.student_id = s.id
        WHERE s.class_name = ? AND a.date = ?
      `;
    const params = isAll ? [date] : [class_name, date];
    if (shift_id) {
      query += ' AND (a.shift_id = ? OR (a.shift_id IS NULL AND ? = \'\'))';
      params.push(shift_id, shift_id);
    }

    const attendanceRecords = db.prepare(query).all(...params);

    const recordMap = {};
    attendanceRecords.forEach(r => {
      recordMap[r.student_id] = {
        status: r.status,
        remarks: r.remarks,
        check_in_time: r.check_in_time || '',
        check_out_time: r.check_out_time || '',
        verification_method: r.verification_method || 'Manual',
        shift_id: r.shift_id || '',
        shift_name: r.shift_name || ''
      };
    });

    const todayDate = getLocalDateString();
    const now = new Date();
    const currentTotalMinutes = now.getHours() * 60 + now.getMinutes();
    const closeTotalMinutes = getLatestShiftEndMinutes();

    const list = students.map(s => {
      let status = recordMap[s.id]?.status || null;
      if (!status) {
        if (date < todayDate) {
          status = 'Absent';
        }
      }
      return {
        id: s.id,
        registration_number: s.registration_number,
        gr_no: s.gr_no,
        full_name: s.full_name,
        class_name: s.class_name,
        photo_path: s.photo_path || '',
        face_data: s.face_data || null,
        fingerprint_data: s.fingerprint_data || null,
        has_face_enrolled: Boolean((s.face_data && s.face_data.length > 0) || (s.photo_path && s.photo_path.length > 0)),
        has_fingerprint_enrolled: Boolean(s.fingerprint_data && s.fingerprint_data.length > 0),
        status: status,
        remarks: recordMap[s.id]?.remarks || '',
        check_in_time: recordMap[s.id]?.check_in_time || '',
        check_out_time: recordMap[s.id]?.check_out_time || '',
        verification_method: recordMap[s.id]?.verification_method || 'Manual',
        shift_id: recordMap[s.id]?.shift_id || shift_id || '',
        shift_name: recordMap[s.id]?.shift_name || ''
      };
    });

    res.json(list);
  } catch (error) {
    console.error('getStudentAttendance error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ═══════════════════════════════════════════════════════════════════════
// SAVE STUDENT ATTENDANCE
// ═══════════════════════════════════════════════════════════════════════
exports.saveStudentAttendance = (req, res) => {
  try {
    const { date, class_name, attendanceList, shift_id, shift_name } = req.body;
    console.log('saveStudentAttendance body:', { date, class_name, attendanceList, shift_id, shift_name });
    if (!date || !class_name || !Array.isArray(attendanceList)) {
      return res.status(400).json({ error: 'Date, class_name and attendanceList are required' });
    }

    const defaultShiftId = shift_id || '';
    const defaultShiftName = shift_name || '';

    const transaction = db.transaction(() => {
      for (const item of attendanceList) {
        const { student_id, status, remarks, check_in_time, check_out_time, verification_method } = item;
        if (!student_id) continue;

        const sId = item.shift_id !== undefined ? (item.shift_id || '') : defaultShiftId;
        const sName = item.shift_name !== undefined ? (item.shift_name || '') : defaultShiftName;

        if (!status || status === '' || status === 'unmarked' || status === 'reset') {
          db.prepare(`
            DELETE FROM attendance 
            WHERE student_id = ? AND date = ? AND (shift_id = ? OR (shift_id IS NULL AND ? = ''))
          `).run(student_id, date, sId, sId);
          continue;
        }

        let finalCheckIn = check_in_time;
        let finalCheckOut = check_out_time;

        const existing = db.prepare(`
          SELECT id, check_in_time, check_out_time 
          FROM attendance 
          WHERE student_id = ? AND date = ? AND (shift_id = ? OR (shift_id IS NULL AND ? = ''))
        `).get(student_id, date, sId, sId);

        if (existing) {
          if (status === 'Absent') {
            finalCheckIn = '';
            finalCheckOut = '';
          } else {
            if (!finalCheckIn && existing.check_in_time) finalCheckIn = existing.check_in_time;
            if (!finalCheckOut && existing.check_out_time) finalCheckOut = existing.check_out_time;
          }
          db.prepare('UPDATE attendance SET status = ?, remarks = ?, check_in_time = ?, check_out_time = ?, verification_method = ?, shift_id = ?, shift_name = ? WHERE id = ?')
            .run(status, remarks || '', finalCheckIn || '', finalCheckOut || '', verification_method || 'Manual', sId, sName, existing.id);
        } else {
          db.prepare('INSERT INTO attendance (id, student_id, date, status, remarks, check_in_time, check_out_time, verification_method, shift_id, shift_name) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)')
            .run(uuidv4(), student_id, date, status, remarks || '', finalCheckIn || '', finalCheckOut || '', verification_method || 'Manual', sId, sName);
        }

        if (status === 'Absent' || status === 'Late') {
          const student = db.prepare('SELECT full_name, mobile_no FROM students WHERE id = ?').get(student_id);
          if (student && student.mobile_no) {
            console.log(`[Notification Alert] SMS sent to ${student.mobile_no} for student "${student.full_name}": Marked as ${status} on ${date}.`);
          }
        }
      }
    });

    transaction();
    
    db.prepare(`
      INSERT INTO activity_logs (id, user_id, action, module, details, ip_address)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(uuidv4(), req.user?.id || null, 'mark_attendance', 'attendance', `Marked student attendance for class ${class_name} on ${date}`, req.ip);

    res.json({ message: 'Attendance saved successfully' });
  } catch (error) {
    console.error('saveStudentAttendance error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ═══════════════════════════════════════════════════════════════════════
// GET STAFF ATTENDANCE
// ═══════════════════════════════════════════════════════════════════════
exports.getStaffAttendance = (req, res) => {
  try {
    const { date } = req.query;
    if (!date) {
      return res.status(400).json({ error: 'Date is required' });
    }

    const staffList = db.prepare(`
      SELECT id, staff_no, full_name, staff_type, mobile_no
      FROM staff
      WHERE is_active = 1
      ORDER BY full_name ASC
    `).all();

    const attendanceRecords = db.prepare(`
      SELECT sa.staff_id, sa.status, sa.check_in_time, sa.check_out_time, sa.remarks, sa.verification_method
      FROM staff_attendance sa
      WHERE sa.date = ?
    `).all(date);

    const recordMap = {};
    attendanceRecords.forEach(r => {
      recordMap[r.staff_id] = {
        status: r.status,
        check_in_time: r.check_in_time,
        check_out_time: r.check_out_time || '',
        remarks: r.remarks,
        verification_method: r.verification_method
      };
    });

    const todayDate = getLocalDateString();
    const now = new Date();
    const currentTotalMinutes = now.getHours() * 60 + now.getMinutes();
    const closeTotalMinutes = getLatestShiftEndMinutes();

    const list = staffList.map(s => {
      let status = recordMap[s.id]?.status || null;
      if (!status) {
        if (date < todayDate) {
          status = 'Absent';
        }
      }
      return {
        id: s.id,
        staff_no: s.staff_no,
        full_name: s.full_name,
        staff_type: s.staff_type,
        mobile_no: s.mobile_no,
        status: status,
        check_in_time: recordMap[s.id]?.check_in_time || '',
        check_out_time: recordMap[s.id]?.check_out_time || '',
        remarks: recordMap[s.id]?.remarks || '',
        verification_method: recordMap[s.id]?.verification_method || 'Manual'
      };
    });

    res.json(list);
  } catch (error) {
    console.error('getStaffAttendance error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ═══════════════════════════════════════════════════════════════════════
// SAVE STAFF ATTENDANCE
// ═══════════════════════════════════════════════════════════════════════
exports.saveStaffAttendance = (req, res) => {
  try {
    const { attendanceList } = req.body;
    let { date } = req.body;
    if (!Array.isArray(attendanceList)) {
      return res.status(400).json({ error: 'attendanceList is required' });
    }

    const isAdmin = req.user?.roles?.some(r => r.name === 'Admin');
    const todayDate = getLocalDateString();
    if (!date || !isAdmin) {
      date = todayDate;
    }

    const transaction = db.transaction(() => {
      for (const item of attendanceList) {
        const { staff_id, status, remarks, verification_method } = item;
        let { check_in_time, check_out_time } = item;
        if (!staff_id || !status) continue;

        const nowTime = formatTime(new Date());
        if (!isAdmin) {
          check_in_time = check_in_time || nowTime;
        } else {
          check_in_time = check_in_time || nowTime;
        }

        const existing = db.prepare('SELECT id, check_in_time, check_out_time FROM staff_attendance WHERE staff_id = ? AND date = ?').get(staff_id, date);
        if (existing) {
          if (status === 'Absent') {
            check_in_time = '';
            check_out_time = '';
          } else {
            if (!check_in_time && existing.check_in_time) check_in_time = existing.check_in_time;
            if (!check_out_time && existing.check_out_time) check_out_time = existing.check_out_time;
          }
          db.prepare(`
            UPDATE staff_attendance 
            SET status = ?, check_in_time = ?, check_out_time = ?, remarks = ?, verification_method = ? 
            WHERE id = ?
          `).run(status, check_in_time, check_out_time || '', remarks || '', verification_method || 'Manual', existing.id);
        } else {
          db.prepare(`
            INSERT INTO staff_attendance (id, staff_id, date, status, check_in_time, check_out_time, remarks, verification_method)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          `).run(uuidv4(), staff_id, date, status, check_in_time, check_out_time || '', remarks || '', verification_method || 'Manual');
        }
      }
    });

    transaction();

    db.prepare(`
      INSERT INTO activity_logs (id, user_id, action, module, details, ip_address)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(uuidv4(), req.user?.id || null, 'mark_staff_attendance', 'attendance', `Marked staff attendance on ${date}`, req.ip);

    res.json({ message: 'Staff attendance saved successfully' });
  } catch (error) {
    console.error('saveStaffAttendance error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ═══════════════════════════════════════════════════════════════════════
// SCAN ATTENDANCE (QR) — 1st scan = IN, 2nd scan = OUT
// ═══════════════════════════════════════════════════════════════════════
exports.scanAttendance = (req, res) => {
  try {
    const { code } = req.body;
    if (!code) {
      return res.status(400).json({ error: 'Code is required' });
    }

    const todayDate = getLocalDateString();
    const now = new Date();
    const formattedDate = formatDate(now);
    const formattedTime = formatTime(now);

    // Determine P/L based on active shift + grace minutes
    const activeShift = getActiveShift(now);
    const graceMinutesSetting = parseInt(db.prepare('SELECT value FROM settings WHERE key = ?').get('late_grace_minutes')?.value || '15', 10);

    const currentTotalMinutes = now.getHours() * 60 + now.getMinutes();
    let status = 'Present';
    if (activeShift) {
      const [sh, sm] = activeShift.start_time.split(':').map(Number);
      const shiftStartMinutes = sh * 60 + sm;
      let diff = currentTotalMinutes - shiftStartMinutes;
      if (diff < 0) diff += 24 * 60;
      status = (diff <= graceMinutesSetting || diff > 18 * 60) ? 'Present' : 'Late';
    }

    let isStudent = false;
    let isStaff = false;
    let actualCode = code.trim();

    if (actualCode.startsWith('STU:')) {
      actualCode = actualCode.substring(4);
      isStudent = true;
    } else if (actualCode.startsWith('STF:')) {
      actualCode = actualCode.substring(4);
      isStaff = true;
    }

    if (isStudent || (!isStudent && !isStaff)) {
      const student = db.prepare('SELECT id, full_name, mobile_no FROM students WHERE (gr_no = ? OR registration_number = ?) AND is_active = 1').get(actualCode, actualCode);
      if (student) {
        const existing = db.prepare('SELECT id, check_in_time, check_out_time FROM attendance WHERE student_id = ? AND date = ?').get(student.id, todayDate);
        
        let scanType = 'IN';
        if (existing && existing.check_in_time && !existing.check_out_time) {
          // 2nd scan → mark OUT time
          db.prepare('UPDATE attendance SET status = ?, remarks = ?, check_out_time = ? WHERE id = ?')
            .run(status, 'Scanned', formattedTime, existing.id);
          scanType = 'OUT';
        } else if (existing && existing.check_in_time && existing.check_out_time) {
          // Already has both IN and OUT — update OUT time (re-scan)
          db.prepare('UPDATE attendance SET status = ?, remarks = ?, check_out_time = ? WHERE id = ?')
            .run(status, 'Scanned', formattedTime, existing.id);
          scanType = 'OUT';
        } else if (existing) {
          // Record exists but no check_in_time → set IN
          db.prepare('UPDATE attendance SET status = ?, remarks = ?, check_in_time = ? WHERE id = ?')
            .run(status, 'Scanned', formattedTime, existing.id);
        } else {
          // No record → create with IN time
          db.prepare('INSERT INTO attendance (id, student_id, date, status, remarks, check_in_time) VALUES (?, ?, ?, ?, ?, ?)')
            .run(uuidv4(), student.id, todayDate, status, 'Scanned', formattedTime);
        }

        console.log(`[Notification Alert] SMS sent to ${student.mobile_no || 'parent'}: Student "${student.full_name}" checked ${scanType} as ${status} at ${formattedTime} on ${formattedDate}.`);

        return res.json({
          status: 'success',
          name: student.full_name,
          type: 'Student',
          date: formattedDate,
          time: formattedTime,
          attendanceStatus: status,
          scanType: scanType
        });
      }
    }

    if (isStaff || (!isStudent && !isStaff)) {
      const staff = db.prepare('SELECT id, full_name FROM staff WHERE staff_no = ? AND is_active = 1').get(actualCode);
      if (staff) {
        const existing = db.prepare('SELECT id, check_in_time, check_out_time FROM staff_attendance WHERE staff_id = ? AND date = ?').get(staff.id, todayDate);
        
        let scanType = 'IN';
        if (existing && existing.check_in_time && !existing.check_out_time) {
          // 2nd scan → mark OUT time
          db.prepare('UPDATE staff_attendance SET status = ?, remarks = ?, check_out_time = ? WHERE id = ?')
            .run(status, 'Scanned', formattedTime, existing.id);
          scanType = 'OUT';
        } else if (existing && existing.check_in_time && existing.check_out_time) {
          // Already has both → update OUT time
          db.prepare('UPDATE staff_attendance SET status = ?, remarks = ?, check_out_time = ? WHERE id = ?')
            .run(status, 'Scanned', formattedTime, existing.id);
          scanType = 'OUT';
        } else if (existing) {
          db.prepare('UPDATE staff_attendance SET status = ?, check_in_time = ?, remarks = ?, verification_method = ? WHERE id = ?')
            .run(status, formattedTime, 'Scanned', 'Mobile', existing.id);
        } else {
          db.prepare('INSERT INTO staff_attendance (id, staff_id, date, status, check_in_time, remarks, verification_method) VALUES (?, ?, ?, ?, ?, ?, ?)')
            .run(uuidv4(), staff.id, todayDate, status, formattedTime, 'Scanned', 'Mobile');
        }

        return res.json({
          status: 'success',
          name: staff.full_name,
          type: 'Staff',
          date: formattedDate,
          time: formattedTime,
          attendanceStatus: status,
          scanType: scanType
        });
      }
    }

    return res.status(404).json({ error: `No student or staff member found for code: "${code}"` });

  } catch (error) {
    console.error('Scan attendance error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ═══════════════════════════════════════════════════════════════════════
// GET ATTENDANCE BY STUDENT ID (FOR PROFILE & HISTORY TIMELINE)
// ═══════════════════════════════════════════════════════════════════════
exports.getAttendanceByStudentId = (req, res) => {
  try {
    const studentId = req.params.studentId || req.params.id;
    if (!studentId) {
      return res.status(400).json({ error: 'Student ID is required' });
    }

    const { year, month, date } = req.query;
    let filterClause = '';
    const params = [studentId];
    const statParams = [studentId];

    if (date && date.trim().length > 0) {
      filterClause += ' AND date = ?';
      params.push(date.trim());
      statParams.push(date.trim());
    } else if (month && month.trim().length > 0) {
      const mStr = month.trim();
      if (mStr.includes('-')) {
        filterClause += ' AND date LIKE ?';
        params.push(`${mStr}%`);
        statParams.push(`${mStr}%`);
      } else {
        filterClause += ' AND strftime("%m", date) = ?';
        params.push(mStr.padStart(2, '0'));
        statParams.push(mStr.padStart(2, '0'));
      }
    } else if (year && year.trim().length > 0) {
      const yStr = year.trim();
      if (yStr.includes('-')) {
        const parts = yStr.split('-');
        filterClause += ' AND (date >= ? AND date <= ?)';
        params.push(`${parts[0]}-01-01`, `${parts[1]}-12-31`);
        statParams.push(`${parts[0]}-01-01`, `${parts[1]}-12-31`);
      } else {
        filterClause += ' AND strftime("%Y", date) = ?';
        params.push(yStr);
        statParams.push(yStr);
      }
    }

    const records = db.prepare(`
      SELECT * FROM attendance
      WHERE student_id = ? ${filterClause}
      ORDER BY date DESC, created_at DESC
    `).all(...params);

    const stats = db.prepare(`
      SELECT 
        COUNT(*) as total_days,
        SUM(CASE WHEN LOWER(status) IN ('present', 'p', 'hazir') THEN 1 ELSE 0 END) as present_days,
        SUM(CASE WHEN LOWER(status) IN ('absent', 'a', 'ghair hazir') THEN 1 ELSE 0 END) as absent_days,
        SUM(CASE WHEN LOWER(status) IN ('leave', 'l', 'chutti', 'late') THEN 1 ELSE 0 END) as leave_days
      FROM attendance
      WHERE student_id = ? ${filterClause}
    `).get(...statParams);

    const total = stats?.total_days || 0;
    const present = stats?.present_days || 0;
    const absent = stats?.absent_days || 0;
    const leave = stats?.leave_days || 0;
    const pct = total > 0 ? ((present / total) * 100) : 0;

    // Monthly breakdown summary across all available records for this student
    const monthlyStats = db.prepare(`
      SELECT 
        strftime('%Y-%m', date) as month_key,
        COUNT(*) as total_days,
        SUM(CASE WHEN LOWER(status) IN ('present', 'p', 'hazir') THEN 1 ELSE 0 END) as present_days,
        SUM(CASE WHEN LOWER(status) IN ('absent', 'a', 'ghair hazir') THEN 1 ELSE 0 END) as absent_days,
        SUM(CASE WHEN LOWER(status) IN ('leave', 'l', 'chutti', 'late') THEN 1 ELSE 0 END) as leave_days
      FROM attendance
      WHERE student_id = ?
      GROUP BY month_key
      ORDER BY month_key DESC
    `).all(studentId);

    res.json({
      student_id: studentId,
      total_days: total,
      present_days: present,
      absent_days: absent,
      leave_days: leave,
      percentage: Number(pct.toFixed(1)),
      monthly_summary: monthlyStats,
      records: records
    });
  } catch (error) {
    console.error('getAttendanceByStudentId error:', error);
    res.status(500).json({ error: error.message });
  }
};

// ═══════════════════════════════════════════════════════════════════════
// AUTO-SAVE SINGLE STUDENT ATTENDANCE (INSTANT REAL-TIME PERSISTENCE)
// ═══════════════════════════════════════════════════════════════════════
exports.saveSingleStudentAttendance = (req, res) => {
  try {
    const { student_id, date, status, remarks, check_in_time, check_out_time, verification_method, shift_id, shift_name } = req.body;
    if (!student_id || !date) {
      return res.status(400).json({ error: 'student_id and date are required' });
    }

    const sId = shift_id || '';
    const sName = shift_name || '';

    if (!status || status === '' || status === 'unmarked' || status === 'reset') {
      db.prepare(`
        DELETE FROM attendance 
        WHERE student_id = ? AND date = ? AND (shift_id = ? OR (shift_id IS NULL AND ? = ''))
      `).run(student_id, date, sId, sId);

      return res.json({
        status: 'success',
        message: 'Attendance reset/unmarked successfully',
        check_in_time: '',
        check_out_time: '',
        shift_id: sId,
        shift_name: sName
      });
    }

    const existing = db.prepare(`
      SELECT id, check_in_time, check_out_time, shift_id 
      FROM attendance 
      WHERE student_id = ? AND date = ? AND (shift_id = ? OR (shift_id IS NULL AND ? = ''))
    `).get(student_id, date, sId, sId);

    let finalCheckIn = check_in_time !== undefined ? check_in_time : (existing ? existing.check_in_time : '');
    let finalCheckOut = check_out_time !== undefined ? check_out_time : (existing ? existing.check_out_time : '');

    if (status === 'Absent') {
      finalCheckIn = '';
      finalCheckOut = '';
    }

    if (existing) {
      db.prepare(`
        UPDATE attendance 
        SET status = ?, remarks = ?, check_in_time = ?, check_out_time = ?, verification_method = ?, shift_id = ?, shift_name = ? 
        WHERE id = ?
      `).run(status, remarks || '', finalCheckIn || '', finalCheckOut || '', verification_method || 'Manual', sId, sName, existing.id);
    } else {
      db.prepare(`
        INSERT INTO attendance (id, student_id, date, status, remarks, check_in_time, check_out_time, verification_method, shift_id, shift_name) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(uuidv4(), student_id, date, status, remarks || '', finalCheckIn || '', finalCheckOut || '', verification_method || 'Manual', sId, sName);
    }

    res.json({
      status: 'success',
      message: 'Attendance auto-saved successfully',
      check_in_time: finalCheckIn,
      check_out_time: finalCheckOut,
      shift_id: sId,
      shift_name: sName
    });
  } catch (error) {
    console.error('saveSingleStudentAttendance error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ═══════════════════════════════════════════════════════════════════════
// BIOMETRIC ATTENDANCE SCAN (FACE / FINGERPRINT)
// ═══════════════════════════════════════════════════════════════════════
exports.biometricScan = (req, res) => {
  try {
    const { student_id, code, biometric_type, device_mode, remarks } = req.body;
    const type = biometric_type || 'Face'; // 'Face' or 'Fingerprint'
    const scanRemarks = remarks || `Biometric ${type} (${device_mode || 'mobile'})`;

    let student = null;
    if (student_id) {
      student = db.prepare('SELECT * FROM students WHERE id = ? AND is_active = 1').get(student_id);
    } else if (code) {
      student = db.prepare('SELECT * FROM students WHERE (gr_no = ? OR registration_number = ?) AND is_active = 1').get(code.trim(), code.trim());
    }

    if (!student) {
      return res.status(404).json({
        status: 'error',
        code: 'STUDENT_NOT_FOUND',
        message: 'No active student found for this biometric scan.'
      });
    }

    // 1. Enrollment check: Does the student have enrolled biometric data in the system?
    const hasFace = Boolean((student.face_data && student.face_data.length > 0) || (student.photo_path && student.photo_path.length > 0));
    const hasFingerprint = Boolean(student.fingerprint_data && student.fingerprint_data.length > 0);

    if (type === 'Face' && !hasFace) {
      return res.status(400).json({
        status: 'error',
        code: 'NOT_ENROLLED',
        student_id: student.id,
        name: student.full_name,
        message: `Face data is not enrolled for "${student.full_name}". Please enroll face data first.`
      });
    }

    if (type === 'Fingerprint' && !hasFingerprint) {
      return res.status(400).json({
        status: 'error',
        code: 'NOT_ENROLLED',
        student_id: student.id,
        name: student.full_name,
        message: `Fingerprint data is not enrolled for "${student.full_name}". Please enroll fingerprint data first.`
      });
    }

    // 2. Evaluate Madarsa Timings & Grace Period for Late calculation
    const now = new Date();
    const todayDate = getLocalDateString();
    const formattedDate = formatDate(now);
    const formattedTime = formatTime(now);

    const activeShift = getActiveShift(now);
    const graceMinutesSetting = parseInt(db.prepare('SELECT value FROM settings WHERE key = ?').get('late_grace_minutes')?.value || '15', 10);

    const currentTotalMinutes = now.getHours() * 60 + now.getMinutes();
    let status = 'Present';
    if (activeShift) {
      const [sh, sm] = activeShift.start_time.split(':').map(Number);
      const shiftStartMinutes = sh * 60 + sm;
      let diff = currentTotalMinutes - shiftStartMinutes;
      if (diff < 0) diff += 24 * 60;
      status = (diff <= graceMinutesSetting || diff > 18 * 60) ? 'Present' : 'Late';
    }

    // 3. Save attendance record directly (Auto-Save!)
    const existing = db.prepare('SELECT id, check_in_time, check_out_time FROM attendance WHERE student_id = ? AND date = ?').get(student.id, todayDate);
    let scanType = 'IN';

    if (existing && existing.check_in_time && !existing.check_out_time) {
      // 2nd scan of day -> mark OUT
      db.prepare(`
        UPDATE attendance 
        SET status = ?, remarks = ?, check_out_time = ?, verification_method = ? 
        WHERE id = ?
      `).run(status, scanRemarks, formattedTime, type, existing.id);
      scanType = 'OUT';
    } else if (existing) {
      db.prepare(`
        UPDATE attendance 
        SET status = ?, remarks = ?, check_in_time = ?, verification_method = ? 
        WHERE id = ?
      `).run(status, scanRemarks, formattedTime, type, existing.id);
    } else {
      db.prepare(`
        INSERT INTO attendance (id, student_id, date, status, remarks, check_in_time, verification_method) 
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).run(uuidv4(), student.id, todayDate, status, scanRemarks, formattedTime, type);
    }

    return res.json({
      status: 'success',
      student_id: student.id,
      name: student.full_name,
      gr_no: student.gr_no,
      class_name: student.class_name,
      date: formattedDate,
      time: formattedTime,
      attendanceStatus: status,
      scanType: scanType,
      verificationMethod: type,
      deviceMode: device_mode || 'mobile',
      message: `${student.full_name} marked ${status} at ${formattedTime} (${type} Scan - Auto-Saved)`
    });
  } catch (error) {
    console.error('biometricScan error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ═══════════════════════════════════════════════════════════════════════
// BIOMETRIC ENROLLMENT (FACE / FINGERPRINT)
// ═══════════════════════════════════════════════════════════════════════
exports.biometricEnroll = (req, res) => {
  try {
    const { student_id, biometric_type, template_data, photo_path } = req.body;
    if (!student_id || !biometric_type) {
      return res.status(400).json({ error: 'student_id and biometric_type are required' });
    }

    const student = db.prepare('SELECT id, full_name FROM students WHERE id = ?').get(student_id);
    if (!student) {
      return res.status(404).json({ error: 'Student not found' });
    }

    const template = template_data || `enrolled_${Date.now()}`;
    const type = biometric_type.toLowerCase();
    const now = new Date().toISOString();

    if (type.includes('face')) {
      if (photo_path) {
        db.prepare('UPDATE students SET face_data = ?, photo_path = ?, biometric_enrolled_at = ? WHERE id = ?')
          .run(template, photo_path, now, student_id);
      } else {
        db.prepare('UPDATE students SET face_data = ?, biometric_enrolled_at = ? WHERE id = ?')
          .run(template, now, student_id);
      }
    } else if (type.includes('finger')) {
      db.prepare('UPDATE students SET fingerprint_data = ?, biometric_enrolled_at = ? WHERE id = ?')
        .run(template, now, student_id);
    } else {
      return res.status(400).json({ error: 'Invalid biometric_type' });
    }

    res.json({
      status: 'success',
      message: `${biometric_type} successfully enrolled for ${student.full_name}`
    });
  } catch (error) {
    console.error('biometricEnroll error:', error);
    res.status(500).json({ error: error.message || 'Internal server error' });
  }
};

// ═══════════════════════════════════════════════════════════════════════
// CLEAR BIOMETRIC ENROLLMENT (FACE / FINGERPRINT)
// ═══════════════════════════════════════════════════════════════════════
exports.clearBiometric = (req, res) => {
  try {
    const { student_id, biometric_type } = req.body;
    if (!student_id) {
      return res.status(400).json({ error: 'student_id is required' });
    }

    const student = db.prepare('SELECT id, full_name FROM students WHERE id = ?').get(student_id);
    if (!student) {
      return res.status(404).json({ error: 'Student not found' });
    }

    const type = (biometric_type || 'both').toLowerCase();
    if (type.includes('face')) {
      db.prepare('UPDATE students SET face_data = NULL, photo_path = NULL WHERE id = ?').run(student_id);
    } else if (type.includes('finger')) {
      db.prepare('UPDATE students SET fingerprint_data = NULL WHERE id = ?').run(student_id);
    } else {
      db.prepare('UPDATE students SET face_data = NULL, photo_path = NULL, fingerprint_data = NULL WHERE id = ?').run(student_id);
    }

    res.json({
      status: 'success',
      message: `Biometric data cleared successfully for ${student.full_name}`
    });
  } catch (error) {
    console.error('clearBiometric error:', error);
    res.status(500).json({ error: error.message || 'Internal server error' });
  }
};


// ═══════════════════════════════════════════════════════════════════════
// PERIOD-WISE ATTENDANCE (PER CLASS PERIOD)
// ═══════════════════════════════════════════════════════════════════════
exports.getPeriodAttendance = (req, res) => {
  try {
    const { class_id, class_name, date, period_number } = req.query;
    if ((!class_id && !class_name) || !date || period_number === undefined) {
      return res.status(400).json({ error: 'class_id or class_name, date, and period_number are required' });
    }

    const pNum = parseInt(period_number, 10);

    // Resolve class_name and class_id safely to support both class UUID and class name queries
    let targetClassName = (class_name || '').trim();
    let targetClassId = (class_id || '').trim();

    if (!targetClassName && targetClassId) {
      const cls = db.prepare('SELECT id, name FROM classes WHERE id = ? OR name = ?').get(targetClassId, targetClassId);
      if (cls) {
        targetClassName = cls.name;
        targetClassId = cls.id;
      } else {
        targetClassName = targetClassId;
      }
    } else if (!targetClassId && targetClassName) {
      const cls = db.prepare('SELECT id, name FROM classes WHERE name = ? OR id = ?').get(targetClassName, targetClassName);
      if (cls) {
        targetClassId = cls.id;
      } else {
        targetClassId = targetClassName;
      }
    }

    const students = db.prepare(`
      SELECT id, registration_number, gr_no, full_name, class_name, photo_path
      FROM students
      WHERE (class_name = ? OR class_name = ?) AND is_active = 1
      ORDER BY full_name ASC
    `).all(targetClassName || '', class_name || '');

    const records = db.prepare(`
      SELECT * FROM period_attendance
      WHERE (class_id = ? OR class_id = ? OR class_id = ?)
        AND date = ? AND period_number = ?
    `).all(targetClassId || '', class_id || '', targetClassName || '', date, pNum);

    const recordMap = {};
    records.forEach(r => {
      recordMap[r.student_id] = r;
    });

    const list = students.map(s => {
      const rec = recordMap[s.id];
      return {
        student_id: s.id,
        registration_number: s.registration_number,
        gr_no: s.gr_no,
        full_name: s.full_name,
        class_name: s.class_name,
        photo_path: s.photo_path || '',
        status: rec ? rec.status : 'Present',
        time: rec ? rec.time : '',
        remarks: rec ? rec.remarks : ''
      };
    });

    res.json(list);
  } catch (error) {
    console.error('getPeriodAttendance error:', error);
    res.status(500).json({ error: error.message });
  }
};

exports.saveSinglePeriodAttendance = (req, res) => {
  try {
    const { student_id, class_id, period_id, period_number, date, status, time, remarks } = req.body;
    if (!student_id || !class_id || period_number === undefined || !date || !status) {
      return res.status(400).json({ error: 'student_id, class_id, period_number, date and status are required' });
    }

    const pNum = parseInt(period_number, 10);
    const timeFormatted = time || formatTime(new Date());

    const existing = db.prepare(`
      SELECT id FROM period_attendance
      WHERE student_id = ? AND date = ? AND period_number = ?
    `).get(student_id, date, pNum);

    if (existing) {
      db.prepare(`
        UPDATE period_attendance
        SET status = ?, time = ?, remarks = ?, period_id = ?
        WHERE id = ?
      `).run(status, timeFormatted, remarks || '', period_id || '', existing.id);
    } else {
      db.prepare(`
        INSERT INTO period_attendance (id, student_id, class_id, period_id, period_number, date, status, time, remarks)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      `).run(uuidv4(), student_id, class_id, period_id || '', pNum, date, status, timeFormatted, remarks || '');
    }

    // Auto-Bridge to Daily Madarsa Shift Attendance:
    // 1. If student has NO Check-IN today in daily attendance, this period scan becomes their Madarsa Check-IN!
    // 2. If student has no Madarsa Gate Check-OUT (or previous was a period bridge), update check_out_time with this latest period time!
    if (status === 'Present' || status === 'Late') {
      try {
        const dailyAtt = db.prepare('SELECT id, check_in_time, check_out_time, remarks FROM attendance WHERE student_id = ? AND date = ?').get(student_id, date);
        if (!dailyAtt) {
          db.prepare(`
            INSERT INTO attendance (id, student_id, date, status, remarks, check_in_time, check_out_time, verification_method)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          `).run(uuidv4(), student_id, date, status, `Auto-bridged from Period ${pNum} (Check-In)`, timeFormatted, timeFormatted, 'Period Bridge');
        } else {
          let updateCheckIn = false;
          let updateCheckOut = false;
          let newCheckIn = dailyAtt.check_in_time;
          let newCheckOut = dailyAtt.check_out_time;
          let newRemarks = dailyAtt.remarks || '';

          if (!dailyAtt.check_in_time) {
            newCheckIn = timeFormatted;
            newRemarks = `Auto-bridged from Period ${pNum} (Check-In)`;
            updateCheckIn = true;
          }
          if (!dailyAtt.check_out_time || (dailyAtt.remarks && dailyAtt.remarks.includes('Period Bridge'))) {
            newCheckOut = timeFormatted;
            newRemarks = updateCheckIn ? newRemarks : `Auto-bridged from Period ${pNum} (Latest Period Scan)`;
            updateCheckOut = true;
          }

          if (updateCheckIn || updateCheckOut) {
            db.prepare(`
              UPDATE attendance
              SET check_in_time = ?, check_out_time = ?, remarks = ?, verification_method = COALESCE(verification_method, 'Period Bridge')
              WHERE id = ?
            `).run(newCheckIn, newCheckOut, newRemarks, dailyAtt.id);
          }
        }
      } catch (bridgeErr) {
        console.error('Period to daily attendance bridge error:', bridgeErr);
      }
    }

    res.json({
      status: 'success',
      message: 'Period attendance saved and bridged',
      time: timeFormatted
    });
  } catch (error) {
    console.error('saveSinglePeriodAttendance error:', error);
    res.status(500).json({ error: error.message });
  }
};

exports.bulkPeriodAttendance = (req, res) => {
  try {
    const { class_id, period_id, period_number, date, status, student_ids } = req.body;
    if (!class_id || period_number === undefined || !date || !status || !Array.isArray(student_ids)) {
      return res.status(400).json({ error: 'class_id, period_number, date, status and student_ids are required' });
    }

    const pNum = parseInt(period_number, 10);
    const timeFormatted = formatTime(new Date());

    const transaction = db.transaction(() => {
      for (const sId of student_ids) {
        const existing = db.prepare(`
          SELECT id FROM period_attendance
          WHERE student_id = ? AND date = ? AND period_number = ?
        `).get(sId, date, pNum);

        if (existing) {
          db.prepare(`
            UPDATE period_attendance
            SET status = ?, time = ?, period_id = ?
            WHERE id = ?
          `).run(status, timeFormatted, period_id || '', existing.id);
        } else {
          db.prepare(`
            INSERT INTO period_attendance (id, student_id, class_id, period_id, period_number, date, status, time)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          `).run(uuidv4(), sId, class_id, period_id || '', pNum, date, status, timeFormatted);
        }

        // Bridge to daily attendance
        if (status === 'Present' || status === 'Late') {
          const dailyAtt = db.prepare('SELECT id, check_in_time, check_out_time, remarks FROM attendance WHERE student_id = ? AND date = ?').get(sId, date);
          if (!dailyAtt) {
            db.prepare(`
              INSERT INTO attendance (id, student_id, date, status, remarks, check_in_time, check_out_time, verification_method)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            `).run(uuidv4(), sId, date, status, `Auto-bridged from Period ${pNum} (Check-In)`, timeFormatted, timeFormatted, 'Period Bridge');
          } else {
            let updateCheckIn = false;
            let updateCheckOut = false;
            let newCheckIn = dailyAtt.check_in_time;
            let newCheckOut = dailyAtt.check_out_time;
            let newRemarks = dailyAtt.remarks || '';

            if (!dailyAtt.check_in_time) {
              newCheckIn = timeFormatted;
              newRemarks = `Auto-bridged from Period ${pNum} (Check-In)`;
              updateCheckIn = true;
            }
            if (!dailyAtt.check_out_time || (dailyAtt.remarks && dailyAtt.remarks.includes('Period Bridge'))) {
              newCheckOut = timeFormatted;
              newRemarks = updateCheckIn ? newRemarks : `Auto-bridged from Period ${pNum} (Latest Period Scan)`;
              updateCheckOut = true;
            }

            if (updateCheckIn || updateCheckOut) {
              db.prepare(`
                UPDATE attendance
                SET check_in_time = ?, check_out_time = ?, remarks = ?, verification_method = COALESCE(verification_method, 'Period Bridge')
                WHERE id = ?
              `).run(newCheckIn, newCheckOut, newRemarks, dailyAtt.id);
            }
          }
        }
      }
    });

    transaction();

    res.json({
      status: 'success',
      message: `Marked ${student_ids.length} students ${status} for period ${pNum}`,
      time: timeFormatted
    });
  } catch (error) {
    console.error('bulkPeriodAttendance error:', error);
    res.status(500).json({ error: error.message });
  }
};
