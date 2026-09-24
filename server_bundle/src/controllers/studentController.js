const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');
const fs = require('fs');
const path = require('path');

function parseDateFlexible(dateStr) {
  if (!dateStr) return null;
  if (dateStr instanceof Date) return isNaN(dateStr.getTime()) ? null : dateStr;
  const str = String(dateStr).trim();
  if (!str) return null;
  // If DD-MM-YYYY or DD/MM/YYYY
  const dmyMatch = str.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/);
  if (dmyMatch) {
    const day = parseInt(dmyMatch[1], 10);
    const month = parseInt(dmyMatch[2], 10) - 1;
    const year = parseInt(dmyMatch[3], 10);
    return new Date(year, month, day);
  }
  // If YYYY-MM-DD or YYYY/MM/DD
  const ymdMatch = str.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/);
  if (ymdMatch) {
    const year = parseInt(ymdMatch[1], 10);
    const month = parseInt(ymdMatch[2], 10) - 1;
    const day = parseInt(ymdMatch[3], 10);
    return new Date(year, month, day);
  }
  const parsed = new Date(str);
  return isNaN(parsed.getTime()) ? null : parsed;
}

function calculateAge(dob, toDate) {
  if (!dob) return { years: 0, months: 0, days: 0, formatted: '' };
  const birth = parseDateFlexible(dob);
  if (!birth) return { years: 0, months: 0, days: 0, formatted: '' };
  const target = toDate ? (parseDateFlexible(toDate) || new Date()) : new Date();
  
  let years = target.getFullYear() - birth.getFullYear();
  let months = target.getMonth() - birth.getMonth();
  let days = target.getDate() - birth.getDate();
  
  if (days < 0) {
    months--;
    const prevMonth = new Date(target.getFullYear(), target.getMonth(), 0);
    days += prevMonth.getDate();
  }
  if (months < 0) {
    years--;
    months += 12;
  }
  
  let formatted = '';
  if (days > 0) formatted += `${days}Days `;
  if (months > 0) formatted += `${months}Months `;
  if (years > 0) formatted += `${years}Years`;
  
  if (formatted.length === 0) {
    formatted = '0Days';
  }
  
  return { years, months, days, formatted: formatted.trim() };
}

function sanitizeRollNumber(val) {
  if (!val) return null;
  const s = String(val).trim();
  if (!s) return null;
  if (/^\d{4}[-\/\.]\d{1,2}[-\/\.]\d{1,2}/.test(s)) return null;
  if (/^\d{1,2}[-\/\.]\d{1,2}[-\/\.]\d{2,4}/.test(s)) return null;
  return s;
}

function generateGRNo() {
  const currentYear = new Date().getFullYear();
  const yearSuffix = String(currentYear).slice(-2); // e.g. "26"
  const pattern = `_${yearSuffix}-%`;
  
  const results = db.prepare("SELECT gr_no FROM students WHERE gr_no LIKE ?").all(pattern);
  
  let maxLetter = 'A';
  let maxSeq = 0;

  if (results && results.length > 0) {
    results.forEach(row => {
      const match = row.gr_no.match(/^([A-Z])(\d{2})-(\d{4})$/);
      if (match) {
        const letter = match[1];
        const year = match[2];
        const seq = parseInt(match[3], 10);

        if (year === yearSuffix) {
          if (letter > maxLetter) {
            maxLetter = letter;
            maxSeq = seq;
          } else if (letter === maxLetter) {
            if (seq > maxSeq) {
              maxSeq = seq;
            }
          }
        }
      }
    });
  }

  let nextGR = '';
  if (maxSeq === 0) {
    nextGR = `${maxLetter}${yearSuffix}-0001`;
  } else if (maxSeq < 9999) {
    const nextSeq = String(maxSeq + 1).padStart(4, '0');
    nextGR = `${maxLetter}${yearSuffix}-${nextSeq}`;
  } else {
    const nextLetter = String.fromCharCode(maxLetter.charCodeAt(0) + 1);
    nextGR = `${nextLetter}${yearSuffix}-0001`;
  }

  // Safety check loop to guarantee absolute uniqueness in database
  while (true) {
    const exists = db.prepare("SELECT 1 FROM students WHERE gr_no = ?").get(nextGR);
    if (!exists) {
      break;
    }
    // If it somehow exists (e.g. manually entered before), increment it
    const match = nextGR.match(/^([A-Z])(\d{2})-(\d{4})$/);
    if (match) {
      const letter = match[1];
      const year = match[2];
      const seq = parseInt(match[3], 10);
      if (seq < 9999) {
        nextGR = `${letter}${year}-${String(seq + 1).padStart(4, '0')}`;
      } else {
        const nextLetter = String.fromCharCode(letter.charCodeAt(0) + 1);
        nextGR = `${nextLetter}${year}-0001`;
      }
    } else {
      break;
    }
  }

  return nextGR;
}

function formatMobile(mobile) {
  if (!mobile) return '';
  let str = String(mobile).trim();
  if (str.toLowerCase().includes('e+')) {
    const num = Number(str);
    if (!isNaN(num)) str = BigInt(Math.round(num)).toString();
  }
  if (str.endsWith('.0')) str = str.slice(0, -2);
  const cleaned = str.replace(/\D/g, '');
  if (cleaned.length === 10) return `+91 ${cleaned.slice(0, 3)} ${cleaned.slice(3, 6)} ${cleaned.slice(6)}`;
  if (cleaned.length === 12 && cleaned.startsWith('91')) {
    const d10 = cleaned.slice(2);
    return `+91 ${d10.slice(0, 3)} ${d10.slice(3, 6)} ${d10.slice(6)}`;
  }
  return mobile;
}

function formatAadhaar(aadhaar) {
  if (!aadhaar) return '';
  let str = String(aadhaar).trim();
  if (str.toLowerCase().includes('e+')) {
    const num = Number(str);
    if (!isNaN(num)) str = BigInt(Math.round(num)).toString();
  }
  if (str.endsWith('.0')) str = str.slice(0, -2);
  const cleaned = str.replace(/\D/g, '');
  if (cleaned.length === 12) return `${cleaned.slice(0, 4)} ${cleaned.slice(4, 8)} ${cleaned.slice(8)}`;
  return str;
}

exports.getAllStudents = (req, res) => {
  try {
    const students = db.prepare(`
      SELECT s.*, 
             c.name as contributor_name,
             (SELECT COUNT(*) FROM attendance a WHERE a.student_id = s.id) as total_attendance,
             (SELECT COALESCE(SUM(amount), 0) FROM fees f WHERE f.student_id = s.id AND (LOWER(f.status) = 'paid' OR LOWER(f.status) = 'completed' OR f.status IS NULL OR f.status = '')) as paid_fees,
             (CASE 
                WHEN (s.monthly_fees IS NOT NULL AND s.monthly_fees > 0) 
                THEN MAX(0, (s.monthly_fees * 12 + COALESCE(s.admission_fee, 0) + COALESCE(s.book_fee, 0)) - (SELECT COALESCE(SUM(amount), 0) FROM fees f WHERE f.student_id = s.id AND (LOWER(f.status) = 'paid' OR LOWER(f.status) = 'completed' OR f.status IS NULL OR f.status = '')))
                ELSE 0 
              END) as pending_fees
      FROM students s
      LEFT JOIN contributors c ON s.contributor_id = c.id
      ORDER BY s.created_at DESC
    `).all();
    res.json(students);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching students', error: error.message });
  }
};

exports.searchStudents = (req, res) => {
  try {
    const query = req.query.q || '';
    const searchPattern = `%${query}%`;
    const { min_age, max_age, gender, class_name, exclude_allocated } = req.query;

    let queryStr = `
      SELECT * FROM students 
      WHERE is_active = 1
        AND (gr_no LIKE ? 
         OR full_name LIKE ? 
         OR father_name LIKE ? 
         OR surname LIKE ? 
         OR mobile_no LIKE ? 
         OR aadhaar_no LIKE ? 
         OR class_name LIKE ?
         OR registration_number LIKE ?)
    `;
    const params = [searchPattern, searchPattern, searchPattern, searchPattern, searchPattern, searchPattern, searchPattern, searchPattern];

    // Age filter: calculate age from date_of_birth
    if (min_age) {
      queryStr += ` AND date_of_birth IS NOT NULL AND date_of_birth != '' AND CAST((julianday('now') - julianday(date_of_birth)) / 365.25 AS INTEGER) >= ?`;
      params.push(parseInt(min_age, 10));
    }
    if (max_age) {
      queryStr += ` AND date_of_birth IS NOT NULL AND date_of_birth != '' AND CAST((julianday('now') - julianday(date_of_birth)) / 365.25 AS INTEGER) <= ?`;
      params.push(parseInt(max_age, 10));
    }

    // Gender filter
    if (gender) {
      queryStr += ` AND gender = ?`;
      params.push(gender);
    }

    // Class filter
    if (class_name) {
      queryStr += ` AND class_name = ?`;
      params.push(class_name);
    }

    // Exclude students already actively allocated in hostel
    if (exclude_allocated === 'true' || exclude_allocated === '1') {
      queryStr += ` AND id NOT IN (SELECT student_id FROM hostel_allocations WHERE status = 'Active')`;
    }

    queryStr += ` ORDER BY full_name ASC`;

    const students = db.prepare(queryStr).all(...params);
    
    res.json(students);
  } catch (error) {
    res.status(500).json({ message: 'Error searching students', error: error.message });
  }
};

exports.getStudentByGRNo = (req, res) => {
  try {
    const { grNo } = req.params;
    const student = db.prepare(`
      SELECT s.*, c.name as contributor_name 
      FROM students s
      LEFT JOIN contributors c ON s.contributor_id = c.id
      WHERE s.gr_no = ?
    `).get(grNo);
    
    if (!student) {
      return res.status(404).json({ message: 'Student not found with this GR.NO.' });
    }
    
    const admissionAge = calculateAge(student.date_of_birth, student.admission_date);
    const nowAge = calculateAge(student.date_of_birth);
    
    res.json({
      ...student,
      admission_time_age: admissionAge.formatted,
      now_age: nowAge.formatted
    });
  } catch (error) {
    res.status(500).json({ message: 'Error fetching student', error: error.message });
  }
};

exports.getStudentById = (req, res) => {
  try {
    const student = db.prepare(`
      SELECT s.*, c.name as contributor_name 
      FROM students s
      LEFT JOIN contributors c ON s.contributor_id = c.id
      WHERE s.id = ?
    `).get(req.params.id);
    
    if (!student) {
      return res.status(404).json({ message: 'Student not found' });
    }
    
    const documents = db.prepare('SELECT * FROM student_documents WHERE student_id = ? ORDER BY uploaded_at DESC').all(req.params.id);
    student.documents = documents;

    const admissionAge = calculateAge(student.date_of_birth, student.admission_date);
    const nowAge = calculateAge(student.date_of_birth);
    const attCount = db.prepare("SELECT COUNT(*) as cnt FROM attendance WHERE student_id = ? AND LOWER(status) IN ('present', 'p', 'hazir')").get(req.params.id);
    
    res.json({
      ...student,
      total_attendance: attCount?.cnt || 0,
      admission_time_age: admissionAge.formatted,
      now_age: nowAge.formatted
    });
  } catch (error) {
    res.status(500).json({ message: 'Error fetching student details', error: error.message });
  }
};

exports.getNextGRNo = (req, res) => {
  try {
    const nextGR = generateGRNo();
    res.json({ gr_no: nextGR });
  } catch (error) {
    res.status(500).json({ message: 'Error generating GR.NO.', error: error.message });
  }
};

exports.createStudent = (req, res) => {
  try {
    const {
      gr_no, roll_number, full_name, father_name, surname, grand_father_name,
      date_of_birth, village, taluka, district, state, pin_code, address,
      mobile_no, aadhaar_no, class_name, student_status,
      admission_type, admission_date, admission_date_h,
      condition_type, monthly_fees, gender, category, division, photo_path,
      contributor_id, contributor_amount,
      department_id, department_name, sub_departments,
      admission_fee, book_fee, fee_structure
    } = req.body;

    if (!full_name) {
      return res.status(400).json({ message: 'Full Name is required' });
    }

    const id = uuidv4();
    const cleanRollNumber = sanitizeRollNumber(roll_number);
    const finalGRNo = gr_no || generateGRNo();
    const finalAdmissionDate = admission_date || new Date().toISOString().split('T')[0];
    const formattedMobile = formatMobile(mobile_no);
    const formattedAadhaar = formatAadhaar(aadhaar_no);
    const serializedSubDepts = sub_departments
      ? (typeof sub_departments === 'string' ? sub_departments : JSON.stringify(sub_departments))
      : null;
    const serializedFeeStructure = fee_structure
      ? (typeof fee_structure === 'string' ? fee_structure : JSON.stringify(fee_structure))
      : null;

    const existing = db.prepare('SELECT id FROM students WHERE gr_no = ?').get(finalGRNo);
    if (existing) {
      // Update existing student record with new fields instead of failing with 400
      const updateStmt = db.prepare(`
        UPDATE students 
        SET full_name = COALESCE(?, full_name),
            father_name = COALESCE(?, father_name),
            surname = COALESCE(?, surname),
            grand_father_name = COALESCE(?, grand_father_name),
            roll_number = COALESCE(?, roll_number),
            date_of_birth = COALESCE(?, date_of_birth),
            village = COALESCE(?, village),
            taluka = COALESCE(?, taluka),
            district = COALESCE(?, district),
            state = COALESCE(?, state),
            pin_code = COALESCE(?, pin_code),
            address = COALESCE(?, address),
            mobile_no = COALESCE(?, mobile_no),
            aadhaar_no = COALESCE(?, aadhaar_no),
            class_name = COALESCE(?, class_name),
            student_status = COALESCE(?, student_status),
            admission_type = COALESCE(?, admission_type),
            admission_date = COALESCE(?, admission_date),
            admission_date_h = COALESCE(?, admission_date_h),
            condition_type = COALESCE(?, condition_type),
            monthly_fees = COALESCE(?, monthly_fees),
            gender = COALESCE(?, gender),
            category = COALESCE(?, category),
            division = COALESCE(?, division),
            photo_path = COALESCE(?, photo_path),
            contributor_id = COALESCE(?, contributor_id),
            contributor_amount = COALESCE(?, contributor_amount),
            department_id = COALESCE(?, department_id),
            department_name = COALESCE(?, department_name),
            sub_departments = COALESCE(?, sub_departments),
            admission_fee = COALESCE(?, admission_fee),
            book_fee = COALESCE(?, book_fee),
            fee_structure = COALESCE(?, fee_structure)
        WHERE id = ?
      `);

      updateStmt.run(
        full_name ?? null, father_name ?? null, surname ?? null, grand_father_name ?? null,
        cleanRollNumber ?? null,
        date_of_birth ?? null, village ?? null, taluka ?? null, district ?? null, state ?? null, pin_code ?? null, address ?? null,
        formattedMobile ?? null, formattedAadhaar ?? null, class_name ?? null, student_status ?? null,
        admission_type ?? null, finalAdmissionDate ?? null, admission_date_h ?? null,
        condition_type ?? null, monthly_fees !== undefined ? monthly_fees : null, gender ?? null, category ?? null, division ?? null, photo_path ?? null,
        contributor_id ?? null, contributor_amount !== undefined ? contributor_amount : null,
        department_id ?? null, department_name ?? null, serializedSubDepts,
        admission_fee !== undefined ? admission_fee : null,
        book_fee !== undefined ? book_fee : null,
        serializedFeeStructure,
        existing.id
      );

      const admissionAge = calculateAge(date_of_birth, finalAdmissionDate);
      const nowAge = calculateAge(date_of_birth);

      return res.status(200).json({
        success: true,
        message: 'Student updated successfully',
        data: {
          id: existing.id, gr_no: finalGRNo, roll_number, full_name, father_name, surname,
          grand_father_name, date_of_birth, village, taluka, district, state,
          pin_code, address, mobile_no: formattedMobile, aadhaar_no: formattedAadhaar,
          class_name, student_status: student_status || 'Active',
          admission_type: admission_type || 'New', admission_date: finalAdmissionDate,
          admission_date_h, condition_type: condition_type || 'Regular',
          monthly_fees: monthly_fees || 0, gender, category, division,
          department_id, department_name, sub_departments: serializedSubDepts,
          admission_fee: admission_fee || 0, book_fee: book_fee || 0, fee_structure: serializedFeeStructure,
          admission_time_age: admissionAge.formatted,
          now_age: nowAge.formatted
        }
      });
    }

    const stmt = db.prepare(`
      INSERT INTO students (
        id, gr_no, registration_number, roll_number, full_name, father_name, surname,
        grand_father_name, date_of_birth, village, taluka, district, state,
        pin_code, address, mobile_no, aadhaar_no, class_name, student_status,
        admission_type, admission_date, admission_date_h, condition_type,
        monthly_fees, gender, category, division, photo_path, is_active,
        contributor_id, contributor_amount, department_id, department_name, sub_departments,
        admission_fee, book_fee, fee_structure
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    stmt.run(
      id, finalGRNo, finalGRNo, cleanRollNumber ?? null, full_name, father_name ?? null, surname ?? null,
      grand_father_name ?? null, date_of_birth ?? null, village ?? null, taluka ?? null, district ?? null, state ?? null,
      pin_code ?? null, address || null, formattedMobile, formattedAadhaar, class_name ?? null, student_status || 'Active',
      admission_type || 'New', finalAdmissionDate, admission_date_h ?? null,
      condition_type || 'Regular', monthly_fees || 0, gender ?? null, category ?? null, division ?? null, photo_path || null,
      contributor_id || null, contributor_amount || 0,
      department_id || null, department_name || null, serializedSubDepts,
      admission_fee || 0, book_fee || 0, serializedFeeStructure
    );

    const admissionAge = calculateAge(date_of_birth, finalAdmissionDate);
    const nowAge = calculateAge(date_of_birth);

    res.status(201).json({
      success: true,
      message: 'Student created successfully',
      data: {
        id, gr_no: finalGRNo, roll_number: cleanRollNumber, full_name, father_name, surname,
        grand_father_name, date_of_birth, village, taluka, district, state,
        pin_code, address, mobile_no: formattedMobile, aadhaar_no: formattedAadhaar,
        class_name, student_status: student_status || 'Active',
        admission_type: admission_type || 'New', admission_date: finalAdmissionDate,
        admission_date_h, condition_type: condition_type || 'Regular',
        monthly_fees: monthly_fees || 0, gender, category, division,
        department_id, department_name, sub_departments: serializedSubDepts,
        admission_fee: admission_fee || 0, book_fee: book_fee || 0, fee_structure: serializedFeeStructure,
        admission_time_age: admissionAge.formatted,
        now_age: nowAge.formatted
      }
    });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ message: 'GR.NO. already exists' });
    }
    res.status(500).json({ message: 'Error creating student', error: error.message });
  }
};

exports.updateStudent = (req, res) => {
  try {
    const { id } = req.params;
    const {
      gr_no, roll_number, full_name, father_name, surname, grand_father_name,
      date_of_birth, village, taluka, district, state, pin_code, address,
      mobile_no, aadhaar_no, class_name, student_status,
      admission_type, admission_date, admission_date_h,
      condition_type, monthly_fees, gender, category, division, photo_path,
      contributor_id, contributor_amount, is_active,
      department_id, department_name, sub_departments,
      admission_fee, book_fee, fee_structure
    } = req.body;

    const existing = db.prepare('SELECT * FROM students WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Student not found' });
    }

    const cleanRollNumber = roll_number !== undefined ? sanitizeRollNumber(roll_number) : existing.roll_number;
    const formattedMobile = mobile_no ? formatMobile(mobile_no) : existing.mobile_no;
    const formattedAadhaar = aadhaar_no ? formatAadhaar(aadhaar_no) : existing.aadhaar_no;
    const serializedSubDepts = sub_departments !== undefined
      ? (sub_departments ? (typeof sub_departments === 'string' ? sub_departments : JSON.stringify(sub_departments)) : null)
      : existing.sub_departments;
    const serializedFeeStructure = fee_structure !== undefined
      ? (fee_structure ? (typeof fee_structure === 'string' ? fee_structure : JSON.stringify(fee_structure)) : null)
      : existing.fee_structure;

    const stmt = db.prepare(`
      UPDATE students 
      SET gr_no = COALESCE(?, gr_no),
          roll_number = ?,
          full_name = COALESCE(?, full_name),
          father_name = COALESCE(?, father_name),
          surname = COALESCE(?, surname),
          grand_father_name = COALESCE(?, grand_father_name),
          date_of_birth = COALESCE(?, date_of_birth),
          village = COALESCE(?, village),
          taluka = COALESCE(?, taluka),
          district = COALESCE(?, district),
          state = COALESCE(?, state),
          pin_code = COALESCE(?, pin_code),
          address = ?,
          mobile_no = ?,
          aadhaar_no = ?,
          class_name = COALESCE(?, class_name),
          student_status = COALESCE(?, student_status),
          admission_type = COALESCE(?, admission_type),
          admission_date = COALESCE(?, admission_date),
          admission_date_h = COALESCE(?, admission_date_h),
          condition_type = COALESCE(?, condition_type),
          monthly_fees = COALESCE(?, monthly_fees),
          gender = COALESCE(?, gender),
          category = COALESCE(?, category),
          division = COALESCE(?, division),
          photo_path = ?,
          contributor_id = ?,
          contributor_amount = COALESCE(?, contributor_amount),
          is_active = COALESCE(?, is_active),
          department_id = COALESCE(?, department_id),
          department_name = COALESCE(?, department_name),
          sub_departments = ?,
          admission_fee = COALESCE(?, admission_fee),
          book_fee = COALESCE(?, book_fee),
          fee_structure = ?,
          updated_at = datetime('now')
      WHERE id = ?
    `);

    const result = stmt.run(
      gr_no, cleanRollNumber, full_name, father_name, surname, grand_father_name,
      date_of_birth, village, taluka, district, state, pin_code,
      address !== undefined ? address : existing.address,
      formattedMobile, formattedAadhaar, class_name, student_status,
      admission_type, admission_date, admission_date_h,
      condition_type, monthly_fees, gender, category, division,
      photo_path ?? existing.photo_path,
      contributor_id !== undefined ? contributor_id : existing.contributor_id,
      contributor_amount !== undefined ? contributor_amount : existing.contributor_amount,
      is_active !== undefined ? is_active : existing.is_active,
      department_id !== undefined ? department_id : existing.department_id,
      department_name !== undefined ? department_name : existing.department_name,
      serializedSubDepts,
      admission_fee !== undefined ? admission_fee : existing.admission_fee,
      book_fee !== undefined ? book_fee : existing.book_fee,
      serializedFeeStructure,
      id
    );

    if (result.changes === 0) {
      return res.status(404).json({ message: 'Student not found' });
    }

    const updated = db.prepare('SELECT * FROM students WHERE id = ?').get(id);
    const admissionAge = calculateAge(updated.date_of_birth, updated.admission_date);
    const nowAge = calculateAge(updated.date_of_birth);

    res.json({
      success: true,
      message: 'Student updated successfully',
      data: {
        ...updated,
        admission_time_age: admissionAge.formatted,
        now_age: nowAge.formatted
      }
    });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ message: 'GR.NO. already exists' });
    }
    res.status(500).json({ message: 'Error updating student', error: error.message });
  }
};

exports.deleteStudent = (req, res) => {
  try {
    const { id } = req.params;
    
    const documents = db.prepare('SELECT * FROM student_documents WHERE student_id = ?').all(id);
    for (const doc of documents) {
      const filePath = path.join(__dirname, '../../', doc.file_path);
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
      }
    }

    const stmt = db.prepare('DELETE FROM students WHERE id = ?');
    const result = stmt.run(id);

    if (result.changes === 0) {
      return res.status(404).json({ message: 'Student not found' });
    }

    res.json({ success: true, message: 'Student deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting student', error: error.message });
  }
};

exports.getAgeCalculation = (req, res) => {
  try {
    const { dob, date } = req.query;
    if (!dob) {
      return res.status(400).json({ message: 'Date of birth is required' });
    }
    
    const admissionAge = calculateAge(dob, date);
    const nowAge = calculateAge(dob);
    
    res.json({
      admission_time_age: admissionAge.formatted,
      now_age: nowAge.formatted
    });
  } catch (error) {
    res.status(500).json({ message: 'Error calculating age', error: error.message });
  }
};

exports.uploadDocument = (req, res) => {
  try {
    const { id } = req.params;
    const { document_name } = req.body;
    const file = req.file;

    if (!file) {
      return res.status(400).json({ message: 'No document file uploaded' });
    }
    if (!document_name) {
      fs.unlinkSync(file.path);
      return res.status(400).json({ message: 'Document name is required' });
    }

    const student = db.prepare('SELECT id FROM students WHERE id = ?').get(id);
    if (!student) {
      fs.unlinkSync(file.path);
      return res.status(404).json({ message: 'Student not found' });
    }

    const relativePath = 'uploads/documents/' + file.filename;
    const docId = uuidv4();
    const stmt = db.prepare(`
      INSERT INTO student_documents (id, student_id, document_name, file_path)
      VALUES (?, ?, ?, ?)
    `);

    stmt.run(docId, id, document_name, relativePath);

    res.status(201).json({
      success: true,
      message: 'Document uploaded successfully',
      document: { id: docId, student_id: id, document_name, file_path: relativePath }
    });
  } catch (error) {
    if (req.file) fs.unlinkSync(req.file.path);
    res.status(500).json({ message: 'Error uploading document', error: error.message });
  }
};

exports.deleteDocument = (req, res) => {
  try {
    const { id, documentId } = req.params;
    const doc = db.prepare('SELECT * FROM student_documents WHERE id = ? AND student_id = ?').get(documentId, id);
    
    if (!doc) {
      return res.status(404).json({ message: 'Document not found' });
    }
    
    db.prepare('DELETE FROM student_documents WHERE id = ?').run(documentId);
    
    const filePath = path.join(__dirname, '../../', doc.file_path);
    if (fs.existsSync(filePath)) {
      fs.unlinkSync(filePath);
    }
    
    res.json({ success: true, message: 'Document deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting document', error: error.message });
  }
};

exports.getPinCodeDetails = async (req, res) => {
  try {
    const { pinCode } = req.params;
    const { db } = require('../config/database');
    const { v4: uuidv4 } = require('uuid');
    
    // Check locally first
    const results = db.prepare('SELECT * FROM pin_codes WHERE pin_code = ?').all(pinCode);
    
    if (results && results.length > 0) {
      return res.json({
        found: true,
        villages: results.map(r => r.village),
        taluka: results[0].taluka,
        district: results[0].district,
        state: results[0].state
      });
    }

    // If not found locally, fetch from Indian Postal API
    try {
      const response = await fetch(`https://api.postalpincode.in/pincode/${pinCode}`);
      const data = await response.json();
      
      if (data && data[0] && data[0].Status === 'Success') {
        const postOffices = data[0].PostOffice;
        
        const taluka = postOffices[0].Block || postOffices[0].Taluk || postOffices[0].Region || '';
        const district = postOffices[0].District || '';
        const state = postOffices[0].State || '';
        const villages = postOffices.map(po => po.Name);
        
        // Cache in DB for offline use later
        const insertStmt = db.prepare(`
          INSERT INTO pin_codes (id, pin_code, village, taluka, district, state) 
          VALUES (?, ?, ?, ?, ?, ?)
        `);
        
        const transaction = db.transaction(() => {
          for (const village of villages) {
            insertStmt.run(uuidv4(), pinCode, village, taluka, district, state);
          }
        });
        transaction();

        return res.json({
          found: true,
          villages: villages,
          taluka: taluka,
          district: district,
          state: state
        });
      }
    } catch (e) {
      console.error('External API fetch failed for pincode:', pinCode, e);
    }
    
    return res.json({ found: false, message: 'Pin code not found' });
  } catch (error) {
    res.status(500).json({ message: 'Error fetching pin code details', error: error.message });
  }
};

exports.searchVillages = (req, res) => {
  try {
    const { q } = req.query;
    if (!q || q.length < 2) {
      return res.json([]);
    }
    
    const searchPattern = `%${q}%`;
    const villages = db.prepare(`
      SELECT DISTINCT village, taluka, district, state, pin_code 
      FROM pin_codes 
      WHERE village LIKE ? OR taluka LIKE ? 
      ORDER BY village 
      LIMIT 20
    `).all(searchPattern, searchPattern);
    
    res.json(villages);
  } catch (error) {
    res.status(500).json({ message: 'Error searching villages', error: error.message });
  }
};

exports.getAllPinCodes = (req, res) => {
  try {
    const pinCodes = db.prepare('SELECT pin_code, village, taluka, district, state FROM pin_codes ORDER BY pin_code').all();
    res.json(pinCodes);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching pin codes', error: error.message });
  }
};

exports.bulkAssignCategory = (req, res) => {
  try {
    const { studentIds, category } = req.body;
    if (!studentIds || !Array.isArray(studentIds) || studentIds.length === 0) {
      return res.status(400).json({ message: 'studentIds array is required' });
    }

    const placeholders = studentIds.map(() => '?').join(',');
    const stmt = db.prepare(`UPDATE students SET category = ?, updated_at = datetime('now') WHERE id IN (${placeholders})`);
    const result = stmt.run(category, ...studentIds);

    res.json({ success: true, message: `Category assigned to ${result.changes} students` });
  } catch (error) {
    res.status(500).json({ message: 'Error bulk assigning category', error: error.message });
  }
};

exports.bulkAssignDivision = (req, res) => {
  try {
    const { studentIds, division, subDepartmentId, subDepartmentName } = req.body;
    if (!studentIds || !Array.isArray(studentIds) || studentIds.length === 0) {
      return res.status(400).json({ message: 'studentIds array is required' });
    }

    if (subDepartmentId || subDepartmentName) {
      // Sub-department division assignment
      const updateTx = db.transaction(() => {
        for (const id of studentIds) {
          const row = db.prepare('SELECT sub_departments FROM students WHERE id = ?').get(id);
          if (row) {
            let subDepts = [];
            if (row.sub_departments) {
              try {
                subDepts = JSON.parse(row.sub_departments);
                if (!Array.isArray(subDepts)) subDepts = [];
              } catch (_) {
                subDepts = [];
              }
            }
            let found = false;
            for (const sub of subDepts) {
              if (
                (subDepartmentId && String(sub.sub_department_id) === String(subDepartmentId)) ||
                (subDepartmentName && String(sub.sub_department_name) === String(subDepartmentName))
              ) {
                sub.division = division;
                found = true;
              }
            }
            if (!found) {
              subDepts.push({
                sub_department_id: subDepartmentId || null,
                sub_department_name: subDepartmentName || null,
                division: division,
              });
            }
            db.prepare("UPDATE students SET sub_departments = ?, updated_at = datetime('now') WHERE id = ?")
              .run(JSON.stringify(subDepts), id);
          }
        }
      });
      updateTx();
      return res.json({ success: true, message: `Sub-department division assigned to ${studentIds.length} students` });
    }

    const placeholders = studentIds.map(() => '?').join(',');
    const stmt = db.prepare(`UPDATE students SET division = ?, updated_at = datetime('now') WHERE id IN (${placeholders})`);
    const result = stmt.run(division, ...studentIds);

    res.json({ success: true, message: `Division assigned to ${result.changes} students` });
  } catch (error) {
    res.status(500).json({ message: 'Error bulk assigning division', error: error.message });
  }
};

exports.bulkDeleteStudents = (req, res) => {
  try {
    const { studentIds } = req.body;
    if (!studentIds || !Array.isArray(studentIds) || studentIds.length === 0) {
      return res.status(400).json({ message: 'studentIds array is required' });
    }

    const deleteTransaction = db.transaction(() => {
      for (const id of studentIds) {
        // Delete documents files
        const documents = db.prepare('SELECT * FROM student_documents WHERE student_id = ?').all(id);
        for (const doc of documents) {
          const filePath = path.join(__dirname, '../../', doc.file_path);
          if (fs.existsSync(filePath)) {
            fs.unlinkSync(filePath);
          }
        }
        // Delete student documents in DB
        db.prepare('DELETE FROM student_documents WHERE student_id = ?').run(id);
        // Delete student
        db.prepare('DELETE FROM students WHERE id = ?').run(id);
      }
    });

    deleteTransaction();

    res.json({ success: true, message: `Successfully deleted ${studentIds.length} students` });
  } catch (error) {
    res.status(500).json({ message: 'Error bulk deleting students', error: error.message });
  }
};

exports.bulkAssignRollNumbers = (req, res) => {
  try {
    const { rollNumbers, subDepartmentId, subDepartmentName } = req.body; // Array of { studentId, rollNumber }
    if (!rollNumbers || !Array.isArray(rollNumbers) || rollNumbers.length === 0) {
      return res.status(400).json({ message: 'rollNumbers array is required' });
    }

    if (subDepartmentId || subDepartmentName) {
      // Sub-department roll number assignment
      const updateTx = db.transaction(() => {
        for (const item of rollNumbers) {
          if (item.studentId) {
            const row = db.prepare('SELECT sub_departments FROM students WHERE id = ?').get(item.studentId);
            if (row) {
              let subDepts = [];
              if (row.sub_departments) {
                try {
                  subDepts = JSON.parse(row.sub_departments);
                  if (!Array.isArray(subDepts)) subDepts = [];
                } catch (_) {
                  subDepts = [];
                }
              }
              let found = false;
              const rNum = sanitizeRollNumber(item.rollNumber);
              for (const sub of subDepts) {
                if (
                  (subDepartmentId && String(sub.sub_department_id) === String(subDepartmentId)) ||
                  (subDepartmentName && String(sub.sub_department_name) === String(subDepartmentName))
                ) {
                  sub.roll_number = rNum;
                  found = true;
                }
              }
              if (!found) {
                subDepts.push({
                  sub_department_id: subDepartmentId || null,
                  sub_department_name: subDepartmentName || null,
                  roll_number: rNum,
                });
              }
              db.prepare("UPDATE students SET sub_departments = ?, updated_at = datetime('now') WHERE id = ?")
                .run(JSON.stringify(subDepts), item.studentId);
            }
          }
        }
      });
      updateTx();
      return res.json({ success: true, message: `Sub-department roll numbers updated for ${rollNumbers.length} students` });
    }

    const stmt = db.prepare(`UPDATE students SET roll_number = ?, updated_at = datetime('now') WHERE id = ?`);
    const updateTx = db.transaction(() => {
      for (const item of rollNumbers) {
        if (item.studentId) {
          stmt.run(sanitizeRollNumber(item.rollNumber), item.studentId);
        }
      }
    });
    updateTx();

    res.json({ success: true, message: `Roll numbers updated for ${rollNumbers.length} students` });
  } catch (error) {
    res.status(500).json({ message: 'Error bulk assigning roll numbers', error: error.message });
  }
};

exports.bulkAssignStatus = (req, res) => {
  try {
    const { studentIds, status } = req.body;
    if (!studentIds || !Array.isArray(studentIds) || studentIds.length === 0) {
      return res.status(400).json({ message: 'studentIds array is required' });
    }

    const isActiveVal = (status && String(status).toLowerCase() === 'inactive') ? 0 : 1;
    const placeholders = studentIds.map(() => '?').join(',');
    const stmt = db.prepare(`UPDATE students SET student_status = ?, is_active = ?, updated_at = datetime('now') WHERE id IN (${placeholders})`);
    const result = stmt.run(status, isActiveVal, ...studentIds);

    res.json({ success: true, message: `Status updated to "${status}" for ${result.changes} students` });
  } catch (error) {
    res.status(500).json({ message: 'Error bulk assigning status', error: error.message });
  }
};

exports.getStudentAcademicHistory = (req, res) => {
  try {
    const { id } = req.params;
    const history = db.prepare('SELECT * FROM student_academic_history WHERE student_id = ? ORDER BY academic_year DESC, created_at DESC').all(id);
    res.json(history);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching academic history', error: error.message });
  }
};

exports.createStudentAcademicHistory = (req, res) => {
  try {
    const { id } = req.params;
    const record = req.body;
    const historyId = record.id || ('hist_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7));
    
    const stmt = db.prepare(`
      INSERT OR REPLACE INTO student_academic_history (
        id, student_id, academic_year, academic_year_hijri, class_id, class_name,
        department_id, department_name, division, roll_number,
        total_attendance_days, present_days, attendance_percentage,
        total_marks, obtained_marks, exam_percentage, result_grade,
        status, remarks, promoted_at, created_at, updated_at,
        fee_total, fee_paid, fee_pending, per_student_expense, books_marks_json, metadata_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'), ?, ?, ?, ?, ?, ?)
    `);

    stmt.run(
      historyId, id, record.academic_year || record.academicYear, record.academic_year_hijri || record.academicYearHijri,
      record.class_id || record.classId, record.class_name || record.className,
      record.department_id || record.departmentId, record.department_name || record.departmentName,
      record.division, record.roll_number || record.rollNumber,
      record.total_attendance_days ?? record.totalAttendanceDays ?? 0,
      record.present_days ?? record.presentDays ?? 0,
      record.attendance_percentage ?? record.attendancePercentage ?? 0,
      record.total_marks ?? record.totalMarks ?? 0,
      record.obtained_marks ?? record.obtainedMarks ?? 0,
      record.exam_percentage ?? record.examPercentage ?? 0,
      record.result_grade || record.resultGrade,
      record.status || 'Promoted',
      record.remarks || null,
      record.promoted_at || record.promotedAt || new Date().toISOString(),
      record.fee_total ?? record.feeTotal ?? 0,
      record.fee_paid ?? record.feePaid ?? 0,
      record.fee_pending ?? record.feePending ?? 0,
      record.per_student_expense ?? record.perStudentExpense ?? 0,
      record.books_marks_json ?? record.booksMarksJson ?? null,
      record.metadata_json ?? record.metadataJson ?? null
    );

    const saved = db.prepare('SELECT * FROM student_academic_history WHERE id = ?').get(historyId);
    res.status(201).json(saved);
  } catch (error) {
    res.status(500).json({ message: 'Error saving academic history', error: error.message });
  }
};

exports.deleteStudentAcademicHistory = (req, res) => {
  try {
    const { historyId } = req.params;
    db.prepare('DELETE FROM student_academic_history WHERE id = ?').run(historyId);
    res.json({ success: true, message: 'Academic history deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting academic history', error: error.message });
  }
};

exports.bulkPromoteStudents = (req, res) => {
  try {
    const {
      studentIds,
      academicYear,
      academicYearHijri,
      targetClass,
      targetDivision,
      status = 'Promoted',
      remarks
    } = req.body;

    if (!studentIds || !Array.isArray(studentIds) || studentIds.length === 0) {
      return res.status(400).json({ message: 'studentIds array is required' });
    }

    const promoteTx = db.transaction(() => {
      let count = 0;
      for (const sId of studentIds) {
        const student = db.prepare('SELECT * FROM students WHERE id = ?').get(sId);
        if (!student) continue;

        let totalAtt = 0, presentAtt = 0, attPct = 0;
        try {
          const attStat = db.prepare(`
            SELECT 
              COUNT(*) as total_days,
              SUM(CASE WHEN status = 'Present' THEN 1 ELSE 0 END) as present_days
            FROM attendance WHERE student_id = ?
          `).get(sId);
          if (attStat) {
            totalAtt = attStat.total_days || 0;
            presentAtt = attStat.present_days || 0;
            attPct = totalAtt > 0 ? (presentAtt / totalAtt) * 100 : 0;
          }
        } catch (_) {}

        let totMarks = 0, obtMarks = 0, examPct = 0, grade = 'Maqbool (Pass)';
        try {
          const marksStat = db.prepare(`
            SELECT 
              SUM(marks_obtained) as obtained,
              SUM(max_marks) as max_marks
            FROM exam_results WHERE student_id = ?
          `).get(sId);
          if (marksStat && marksStat.max_marks > 0) {
            obtMarks = marksStat.obtained || 0;
            totMarks = marksStat.max_marks || 0;
            examPct = totMarks > 0 ? (obtMarks / totMarks) * 100 : 0;
            if (examPct >= 90) grade = 'Mumtaz (A+)';
            else if (examPct >= 80) grade = 'Jayyid Jiddan (A)';
            else if (examPct >= 70) grade = 'Jayyid (B)';
            else if (examPct >= 60) grade = 'Rasib (C)';
            else if (examPct < 50) grade = 'Rasib (Failed)';
          }
        } catch (_) {}

        const histId = 'hist_' + sId + '_' + Date.now() + '_' + Math.random().toString(36).substring(2, 6);
        db.prepare(`
          INSERT OR REPLACE INTO student_academic_history (
            id, student_id, academic_year, academic_year_hijri, class_id, class_name,
            department_id, department_name, division, roll_number,
            total_attendance_days, present_days, attendance_percentage,
            total_marks, obtained_marks, exam_percentage, result_grade,
            status, remarks, promoted_at, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'), datetime('now'))
        `).run(
          histId, sId,
          academicYear || 'Current Year',
          academicYearHijri || null,
          student.class_id || null,
          student.class_name || 'General',
          student.department_id || null,
          student.department_name || null,
          student.division || null,
          student.roll_number || null,
          totalAtt, presentAtt, attPct,
          totMarks, obtMarks, examPct, grade,
          status || 'Promoted',
          remarks || `Promoted to ${targetClass || 'Next Class'}`
        );

        if (status === 'Farigh' || (targetClass && targetClass.toLowerCase() === 'farigh')) {
          db.prepare(`
            UPDATE students SET
              student_status = 'Farigh',
              updated_at = datetime('now')
            WHERE id = ?
          `).run(sId);
        } else {
          const updates = [];
          const params = [];
          if (targetClass) {
            updates.push('class_name = ?');
            params.push(targetClass);
          }
          if (targetDivision) {
            updates.push('division = ?');
            params.push(targetDivision);
          }
          if (status) {
            updates.push('student_status = ?');
            params.push(status);
          }
          updates.push("updated_at = datetime('now')");
          params.push(sId);

          db.prepare(`UPDATE students SET ${updates.join(', ')} WHERE id = ?`).run(...params);
        }
        count++;
      }
      return count;
    });

    const count = promoteTx();
    res.json({ success: true, message: `Successfully updated / promoted ${count} students` });
  } catch (error) {
    res.status(500).json({ message: 'Error bulk promoting students', error: error.message });
  }
};
