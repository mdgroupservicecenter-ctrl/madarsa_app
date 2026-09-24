const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

exports.getStudentFeeSummaries = (req, res) => {
  try {
    const students = db.prepare(`
      SELECT s.id, s.gr_no, s.full_name, s.father_name, s.surname, s.class_name, s.monthly_fees, s.admission_fee, s.book_fee, s.fee_structure, s.mobile_no
      FROM students s
      ORDER BY s.class_name, s.full_name
    `).all();

    // Fetch fee payments grouped by student and fee_type
    const paymentsGrouped = db.prepare(`
      SELECT student_id, fee_type, SUM(amount) as paid_amount
      FROM fees
      WHERE (LOWER(status) = 'paid' OR LOWER(status) = 'completed' OR status IS NULL OR status = '')
      GROUP BY student_id, fee_type
    `).all();

    const paymentsMap = {};
    for (const p of paymentsGrouped) {
      if (!paymentsMap[p.student_id]) paymentsMap[p.student_id] = {};
      const key = (p.fee_type || 'Tuition Fee').toLowerCase().trim();
      paymentsMap[p.student_id][key] = (paymentsMap[p.student_id][key] || 0) + (p.paid_amount || 0);
    }

    const summaries = students.map(s => {
      const studentPaidMap = paymentsMap[s.id] || {};
      let feeHeads = [];

      if (s.fee_structure) {
        try {
          const parsed = typeof s.fee_structure === 'string' ? JSON.parse(s.fee_structure) : s.fee_structure;
          if (Array.isArray(parsed) && parsed.length > 0) {
            feeHeads = parsed.map(item => {
              const name = item.fee_type_name || item.fee_type || 'Fee';
              const amt = Number(item.amount) || 0;
              const billing = item.billing_type || 'monthly';
              const months = billing === 'monthly' ? (Number(item.months_count) || 12) : 1;
              const expected = billing === 'monthly' ? amt * months : amt;
              
              const key = name.toLowerCase().trim();
              const paid = studentPaidMap[key] || 0;
              const pending = Math.max(0, expected - paid);

              return {
                fee_type_id: item.fee_type_id || null,
                fee_type_name: name,
                amount: amt,
                billing_type: billing,
                months_count: months,
                total_expected: expected,
                total_paid: paid,
                total_pending: pending
              };
            });
          }
        } catch (e) {}
      }

      // If no fee_structure parsed, fallback to monthly_fees + admission_fee + book_fee
      if (feeHeads.length === 0) {
        const monthly = Number(s.monthly_fees) || 0;
        const admission = Number(s.admission_fee) || 0;
        const book = Number(s.book_fee) || 0;

        let tuitionPaid = studentPaidMap['tuition fee'] || studentPaidMap['monthly fee'] || studentPaidMap['fee'] || 0;
        let admissionPaid = studentPaidMap['admission fee'] || studentPaidMap['admission'] || 0;
        let bookPaid = studentPaidMap['book fee'] || studentPaidMap['books'] || 0;

        const totalPaidAll = Number(s.total_paid) || 0;
        if (admissionPaid === 0 && bookPaid === 0 && tuitionPaid === 0 && totalPaidAll > 0) {
          tuitionPaid = totalPaidAll;
        }

        feeHeads.push({
          fee_type_name: 'Tuition Fee',
          amount: monthly,
          billing_type: 'monthly',
          months_count: 12,
          total_expected: monthly * 12,
          total_paid: tuitionPaid,
          total_pending: Math.max(0, (monthly * 12) - tuitionPaid)
        });

        if (admission > 0) {
          feeHeads.push({
            fee_type_name: 'Admission Fee',
            amount: admission,
            billing_type: 'one_time',
            months_count: 1,
            total_expected: admission,
            total_paid: admissionPaid,
            total_pending: Math.max(0, admission - admissionPaid)
          });
        }

        if (book > 0) {
          feeHeads.push({
            fee_type_name: 'Book Fee',
            amount: book,
            billing_type: 'yearly',
            months_count: 1,
            total_expected: book,
            total_paid: bookPaid,
            total_pending: Math.max(0, book - bookPaid)
          });
        }
      }

      const totalExpected = feeHeads.reduce((sum, h) => sum + h.total_expected, 0);
      let totalPaidFromHeads = feeHeads.reduce((sum, h) => sum + h.total_paid, 0);
      let totalPaidAll = 0;
      for (const val of Object.values(studentPaidMap)) {
        totalPaidAll += Number(val) || 0;
      }
      const totalPaid = Math.max(totalPaidFromHeads, totalPaidAll);
      const totalPending = Math.max(0, totalExpected - totalPaid);

      return {
        id: s.id,
        gr_no: s.gr_no,
        full_name: s.full_name,
        father_name: s.father_name || null,
        surname: s.surname || null,
        class_name: s.class_name,
        monthly_fees: Number(s.monthly_fees) || 0,
        admission_fee: Number(s.admission_fee) || 0,
        book_fee: Number(s.book_fee) || 0,
        total_expected: totalExpected,
        total_paid: totalPaid,
        total_pending: totalPending,
        mobile_no: s.mobile_no || null,
        fee_heads: feeHeads
      };
    });

    res.json(summaries);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.getStudentPayments = (req, res) => {
  try {
    const { studentId } = req.params;
    const { year, month, date } = req.query;
    let filter = '';
    const params = [studentId];

    if (date && date.trim().length > 0) {
      filter += ' AND payment_date = ?';
      params.push(date.trim());
    } else if (month && month.trim().length > 0) {
      filter += ' AND payment_date LIKE ?';
      params.push(`${month.trim()}%`);
    } else if (year && year.trim().length > 0) {
      const yStr = year.trim();
      if (yStr.includes('-')) {
        const parts = yStr.split('-');
        filter += ' AND (payment_date >= ? AND payment_date <= ?)';
        params.push(`${parts[0]}-01-01`, `${parts[1]}-12-31`);
      } else {
        filter += ' AND strftime("%Y", payment_date) = ?';
        params.push(yStr);
      }
    }

    const payments = db.prepare(`
      SELECT * FROM fees 
      WHERE student_id = ? AND (LOWER(status) = 'paid' OR LOWER(status) = 'completed' OR status IS NULL OR status = '') ${filter}
      ORDER BY COALESCE(created_at, payment_date) DESC, payment_date DESC
    `).all(...params);
    
    res.json(payments);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.payFee = (req, res) => {
  try {
    const { student_id, amount, fee_type, payment_date, remarks, receipt_no } = req.body;
    if (!student_id || !amount || !fee_type) {
      return res.status(400).json({ error: 'student_id, amount, and fee_type are required' });
    }

    const id = uuidv4();
    const finalDate = payment_date || new Date().toISOString().split('T')[0];
    const nowIso = new Date().toISOString();

    try {
      db.prepare(`
        INSERT INTO fees (id, student_id, amount, payment_date, fee_type, status, created_at, remarks, receipt_no)
        VALUES (?, ?, ?, ?, ?, 'Paid', ?, ?, ?)
      `).run(id, student_id, amount, finalDate, fee_type, nowIso, remarks || null, receipt_no || null);
    } catch (_) {
      try {
        db.prepare(`
          INSERT INTO fees (id, student_id, amount, payment_date, fee_type, status, created_at, remarks)
          VALUES (?, ?, ?, ?, ?, 'Paid', ?, ?)
        `).run(id, student_id, amount, finalDate, fee_type, nowIso, remarks || null);
      } catch (__) {
        db.prepare(`
          INSERT INTO fees (id, student_id, amount, payment_date, fee_type, status, created_at)
          VALUES (?, ?, ?, ?, ?, 'Paid', ?)
        `).run(id, student_id, amount, finalDate, fee_type, nowIso);
      }
    }

    // Get student details for SMS
    const student = db.prepare('SELECT full_name, mobile_no, monthly_fees FROM students WHERE id = ?').get(student_id);
    const totalPaid = db.prepare("SELECT COALESCE(SUM(amount),0) as total FROM fees WHERE student_id = ? AND status = 'Paid'").get(student_id);
    const expectedYearly = (student?.monthly_fees || 0) * 12;
    const remainingBalance = expectedYearly - (totalPaid?.total || 0);

    // Send SMS notification for fee payment
    if (student?.mobile_no) {
      const smsMessage = `Assalamu Alaikum, ${student.full_name} ki fees Rs.${amount} jama ho gayi. Baqi balance: Rs.${Math.max(0, remainingBalance)}. Shukriya! - Madarsa Management`;
      sendSMS(student.mobile_no, smsMessage);
    }

    res.status(201).json({ 
      id, student_id, amount, payment_date: finalDate, fee_type, status: 'Paid',
      created_at: nowIso,
      remarks: remarks || null,
      receipt_no: receipt_no || null,
      sms_sent: !!student?.mobile_no
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ─── SMS Service ─────────────────────────────────────────────────
function sendSMS(phoneNumber, message) {
  // Log the SMS for now - integrate with real SMS gateway (MSG91, Twilio, etc.)
  console.log(`📱 SMS → ${phoneNumber}: ${message}`);
  
  // TODO: Integrate with your SMS provider
  // Example with MSG91:
  // const axios = require('axios');
  // axios.post('https://api.msg91.com/api/v5/flow/', {
  //   template_id: 'YOUR_TEMPLATE_ID',
  //   short_url: '0',
  //   mobiles: phoneNumber,
  //   message: message
  // }, { headers: { authkey: 'YOUR_AUTH_KEY' } });
}

// Monthly overdue fee check - call this via cron or scheduled task
exports.checkOverdueFees = (req, res) => {
  try {
    const students = db.prepare(`
      SELECT s.id, s.full_name, s.mobile_no, s.monthly_fees,
             COALESCE((SELECT SUM(amount) FROM fees f WHERE f.student_id = s.id AND f.status = 'Paid'), 0) as total_paid
      FROM students s
      WHERE s.is_active = 1 AND s.mobile_no IS NOT NULL AND s.mobile_no != ''
    `).all();

    let smsSent = 0;
    const currentMonth = new Date().getMonth() + 1; // 1-12
    
    for (const s of students) {
      const expected = (s.monthly_fees || 0) * currentMonth;
      const pending = expected - (s.total_paid || 0);
      
      if (pending > 0) {
        const smsMessage = `Assalamu Alaikum, ${s.full_name} ki ${currentMonth} mahine ki fees me se Rs.${pending} baqi he. Jaldi jama karein. - Madarsa Management`;
        sendSMS(s.mobile_no, smsMessage);
        smsSent++;
      }
    }

    res.json({ message: `Overdue SMS sent to ${smsSent} students`, count: smsSent });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ─── Donations ───────────────────────────────────────────────────
exports.getDonations = (req, res) => {
  try {
    const donations = db.prepare('SELECT * FROM donations ORDER BY payment_date DESC, created_at DESC').all();
    res.json(donations);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createDonation = (req, res) => {
  try {
    const {
      receipt_no,
      donor_name,
      donor_phone,
      village,
      taluka,
      district,
      state,
      country,
      pin_code,
      amount,
      donation_type,
      payment_method,
      payment_date,
    } = req.body;
    if (!amount || !donation_type) {
      return res.status(400).json({ error: 'amount and donation_type are required' });
    }

    const id = uuidv4();
    const finalDate = payment_date || new Date().toISOString().split('T')[0];

    db.prepare(`
      INSERT INTO donations (
        id, receipt_no, donor_name, donor_phone, village, taluka, district, state, country, pin_code,
        amount, donation_type, payment_method, payment_date
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id,
      receipt_no || null,
      donor_name || null,
      donor_phone || null,
      village || null,
      taluka || null,
      district || null,
      state || null,
      country || 'India',
      pin_code || null,
      amount,
      donation_type,
      payment_method || 'Cash',
      finalDate
    );

    res.status(201).json({
      id,
      receipt_no,
      donor_name,
      donor_phone,
      village,
      taluka,
      district,
      state,
      country: country || 'India',
      pin_code,
      amount,
      donation_type,
      payment_method,
      payment_date: finalDate,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ─── Donation Types CRUD ─────────────────────────────────────────
exports.getDonationTypes = (req, res) => {
  try {
    const types = db.prepare('SELECT * FROM donation_types ORDER BY name ASC').all();
    res.json(types);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createDonationType = (req, res) => {
  try {
    const { name } = req.body;
    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    const id = uuidv4();
    db.prepare('INSERT INTO donation_types (id, name) VALUES (?, ?)').run(id, name);

    res.status(201).json({ id, name });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Donation category already exists' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.updateDonationType = (req, res) => {
  try {
    const { id } = req.params;
    const { name } = req.body;
    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    const result = db.prepare('UPDATE donation_types SET name = ? WHERE id = ?').run(name, id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Donation type not found' });
    }

    res.json({ id, name });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Category name already exists' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.deleteDonationType = (req, res) => {
  try {
    const { id } = req.params;
    const result = db.prepare('DELETE FROM donation_types WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Donation type not found' });
    }

    res.json({ message: 'Donation type deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ─── Fee Types CRUD ──────────────────────────────────────────────
exports.getFeeTypes = (req, res) => {
  try {
    const types = db.prepare('SELECT * FROM fee_types ORDER BY name ASC').all();
    res.json(types);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

exports.createFeeType = (req, res) => {
  try {
    const { name, billing_type, default_months, default_amount } = req.body;
    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    const id = uuidv4();
    const billingType = billing_type || 'monthly';
    const defMonths = default_months !== undefined ? Number(default_months) : 12;
    const defAmount = default_amount !== undefined ? Number(default_amount) : 0;

    db.prepare('INSERT INTO fee_types (id, name, billing_type, default_months, default_amount) VALUES (?, ?, ?, ?, ?)').run(id, name, billingType, defMonths, defAmount);

    res.status(201).json({ id, name, billing_type: billingType, default_months: defMonths, default_amount: defAmount });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Fee type already exists' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.updateFeeType = (req, res) => {
  try {
    const { id } = req.params;
    const { name, billing_type, default_months, default_amount } = req.body;
    if (!name) {
      return res.status(400).json({ error: 'name is required' });
    }

    const result = db.prepare(`
      UPDATE fee_types 
      SET name = ?, 
          billing_type = COALESCE(?, billing_type), 
          default_months = COALESCE(?, default_months), 
          default_amount = COALESCE(?, default_amount) 
      WHERE id = ?
    `).run(name, billing_type ?? null, default_months !== undefined ? Number(default_months) : null, default_amount !== undefined ? Number(default_amount) : null, id);

    if (result.changes === 0) {
      return res.status(404).json({ error: 'Fee type not found' });
    }

    const updated = db.prepare('SELECT * FROM fee_types WHERE id = ?').get(id);
    res.json(updated);
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ error: 'Fee type name already exists' });
    }
    res.status(500).json({ error: error.message });
  }
};

exports.deleteFeeType = (req, res) => {
  try {
    const { id } = req.params;
    const result = db.prepare('DELETE FROM fee_types WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Fee type not found' });
    }

    res.json({ message: 'Fee type deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ─── Delete Fee Payment Entry ─────────────────────────────────────
exports.deleteFeePayment = (req, res) => {
  try {
    const { id } = req.params;
    const result = db.prepare('DELETE FROM fees WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Fee payment not found' });
    }
    res.json({ message: 'Fee payment deleted successfully', id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

// ─── Delete Donation Entry ────────────────────────────────────────
exports.deleteDonation = (req, res) => {
  try {
    const { id } = req.params;
    const result = db.prepare('DELETE FROM donations WHERE id = ?').run(id);
    if (result.changes === 0) {
      return res.status(404).json({ error: 'Donation not found' });
    }
    res.json({ message: 'Donation deleted successfully', id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};
