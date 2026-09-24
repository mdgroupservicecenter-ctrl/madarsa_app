const { db } = require('../config/database');

const reportController = {
  getAttendanceSummary(req, res) {
    try {
      const { startDate, endDate, class_name } = req.query;
      
      let query = `
        SELECT a.date, a.status, COUNT(*) as count
        FROM attendance a
        JOIN students s ON a.student_id = s.id
        WHERE 1=1
      `;
      const params = [];

      if (startDate) {
        query += ' AND a.date >= ?';
        params.push(startDate);
      }
      if (endDate) {
        query += ' AND a.date <= ?';
        params.push(endDate);
      }
      if (class_name && class_name !== 'All') {
        query += ' AND s.class_name = ?';
        params.push(class_name);
      }

      query += ' GROUP BY a.date, a.status ORDER BY a.date DESC';

      const results = db.prepare(query).all(...params);

      // Fetch absent students details
      let absentQuery = `
        SELECT a.date, s.full_name, s.gr_no
        FROM attendance a
        JOIN students s ON a.student_id = s.id
        WHERE a.status = 'Absent'
      `;
      const absentParams = [];
      if (startDate) {
        absentQuery += ' AND a.date >= ?';
        absentParams.push(startDate);
      }
      if (endDate) {
        absentQuery += ' AND a.date <= ?';
        absentParams.push(endDate);
      }
      if (class_name && class_name !== 'All') {
        absentQuery += ' AND s.class_name = ?';
        absentParams.push(class_name);
      }
      absentQuery += ' ORDER BY a.date DESC, s.full_name ASC';

      const absentList = db.prepare(absentQuery).all(...absentParams);

      const absentByDate = {};
      absentList.forEach(row => {
        if (!absentByDate[row.date]) {
          absentByDate[row.date] = [];
        }
        absentByDate[row.date].push(`${row.full_name} (${row.gr_no})`);
      });
      
      // Pivot data for easier frontend consumption
      const formatted = {};
      results.forEach(row => {
        if (!formatted[row.date]) {
          formatted[row.date] = { date: row.date, present: 0, absent: 0, late: 0, absent_names: [] };
        }
        formatted[row.date][row.status.toLowerCase()] = row.count;
      });

      // Merge absent names
      Object.keys(formatted).forEach(dt => {
        formatted[dt].absent_names = absentByDate[dt] || [];
      });

      res.json({ reports: Object.values(formatted) });
    } catch (error) {
      console.error('Attendance report error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  getFeeSummary(req, res) {
    try {
      const { startDate, endDate } = req.query;
      
      let queryCollected = `SELECT SUM(amount) as total FROM fees WHERE status = 'Paid'`;
      let queryPending = `SELECT SUM(amount) as total FROM fees WHERE status = 'Pending'`;
      const params = [];

      if (startDate && endDate) {
        queryCollected += ' AND payment_date BETWEEN ? AND ?';
        params.push(startDate, endDate);
      }

      const totalCollected = db.prepare(queryCollected).get(...params).total || 0;
      const totalPending = db.prepare(queryPending).get().total || 0;

      const feeTypes = db.prepare(`
        SELECT fee_type, status, SUM(amount) as total
        FROM fees
        GROUP BY fee_type, status
      `).all();

      res.json({ 
        summary: {
          totalCollected,
          totalPending,
          totalExpected: totalCollected + totalPending
        },
        breakdown: feeTypes
      });
    } catch (error) {
      console.error('Fee report error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  getStudentStats(req, res) {
    try {
      const classStats = db.prepare(`
        SELECT class_name, COUNT(*) as count,
               SUM(CASE WHEN gender = 'Male' THEN 1 ELSE 0 END) as male,
               SUM(CASE WHEN gender = 'Female' THEN 1 ELSE 0 END) as female
        FROM students
        WHERE is_active = 1
        GROUP BY class_name
      `).all();

      const totalStudents = db.prepare('SELECT COUNT(*) as count FROM students WHERE is_active = 1').get().count;
      const genderStats = db.prepare(`
        SELECT gender, COUNT(*) as count 
        FROM students 
        WHERE is_active = 1 
        GROUP BY gender
      `).all();

      res.json({
        total: totalStudents,
        byClass: classStats,
        byGender: genderStats
      });
    } catch (error) {
      console.error('Student stats error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  }
};

module.exports = reportController;
