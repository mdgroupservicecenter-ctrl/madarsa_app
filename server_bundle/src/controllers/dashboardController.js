const { db } = require('../config/database');

exports.getDashboardSummary = (req, res) => {
  try {
    // 1. Total Students
    let totalStudents = 0;
    try {
      const studentCountRow = db.prepare('SELECT COUNT(*) as count FROM students WHERE is_active = 1').get();
      totalStudents = studentCountRow.count;
    } catch (e) {
      console.error('Error fetching students count:', e);
    }

    // 2. Total Staff (Querying staff table properly instead of users)
    let totalStaff = 0;
    try {
      const staffCountRow = db.prepare('SELECT COUNT(*) as count FROM staff WHERE is_active = 1').get();
      totalStaff = staffCountRow.count;
    } catch(e) {
      console.error('Error fetching staff count:', e);
    }

    // 3. Attendance Today (Percentage present)
    const today = new Date().toISOString().split('T')[0];
    let attendancePercentage = '0%';
    try {
      const attendanceToday = db.prepare('SELECT status, COUNT(*) as count FROM attendance WHERE date = ? GROUP BY status').all(today);
      let presentCount = 0;
      let totalCount = 0;
      attendanceToday.forEach(row => {
        totalCount += row.count;
        if (row.status === 'Present') {
          presentCount = row.count;
        }
      });
      if (totalCount > 0) {
        attendancePercentage = Math.round((presentCount / totalCount) * 100) + '%';
      }
    } catch(e) {
      console.error('Error fetching attendance:', e);
    }

    // 4. Pending Fees
    let pendingFees = 0;
    try {
      const feesRow = db.prepare("SELECT SUM(amount) as total FROM fees WHERE status = 'Pending'").get();
      pendingFees = feesRow.total || 0;
    } catch(e) {
      console.error('Error fetching pending fees:', e);
    }

    // 5. Total Donations
    let totalDonations = 0;
    try {
      const donationsRow = db.prepare('SELECT SUM(amount) as total FROM donations').get();
      totalDonations = donationsRow.total || 0;
    } catch (e) {
      console.error('Error fetching total donations:', e);
    }

    // 6. Active Classes Count
    let activeClasses = 0;
    try {
      const classesRow = db.prepare('SELECT COUNT(*) as count FROM classes WHERE is_active = 1').get();
      activeClasses = classesRow.count || 0;
    } catch (e) {
      console.error('Error fetching classes:', e);
    }

    // 7. Hostel Beds Occupied and Total Beds
    let hostelOccupiedBeds = 0;
    let hostelTotalBeds = 0;
    try {
      const occupiedRow = db.prepare("SELECT COUNT(*) as count FROM hostel_allocations WHERE status = 'Active'").get();
      hostelOccupiedBeds = occupiedRow.count || 0;
      
      const totalBedsRow = db.prepare("SELECT COUNT(*) as total FROM hostel_beds").get();
      hostelTotalBeds = totalBedsRow.total || 0;
    } catch (e) {
      console.error('Error fetching hostel stats:', e);
    }

    // 8. Kitchen Low Stock Count
    let kitchenLowStock = 0;
    try {
      const lowStockRow = db.prepare('SELECT COUNT(*) as count FROM kitchen_stock WHERE quantity <= min_threshold').get();
      kitchenLowStock = lowStockRow.count || 0;
    } catch (e) {
      console.error('Error fetching kitchen stock details:', e);
    }

    // 9. General Low Stock Count
    let generalLowStock = 0;
    try {
      const lowStockRow = db.prepare('SELECT COUNT(*) as count FROM general_stock WHERE quantity <= min_threshold').get();
      generalLowStock = lowStockRow.count || 0;
    } catch (e) {
      console.error('Error fetching general stock details:', e);
    }

    // 10. Total Purchase Expenses
    let totalPurchases = 0;
    try {
      const purchaseStats = db.prepare("SELECT SUM(total_price) as total FROM purchase_sell_transactions WHERE type = 'Purchase'").get();
      totalPurchases = purchaseStats.total || 0;
    } catch (e) {
      console.error('Error fetching total purchases:', e);
    }

    // 11. Total Sales Income
    let totalSales = 0;
    try {
      const salesStats = db.prepare("SELECT SUM(total_price) as total FROM purchase_sell_transactions WHERE type = 'Sell'").get();
      totalSales = salesStats.total || 0;
    } catch (e) {
      console.error('Error fetching total sales:', e);
    }

    // 12. Recent Activity
    let recentActivity = [];
    try {
      recentActivity = db.prepare('SELECT * FROM activity_logs ORDER BY created_at DESC LIMIT 5').all();
    } catch(e) {
      console.error('Error fetching activity logs:', e);
    }

    // 13. Total Library Books & Issued Books
    let totalBooks = 0;
    let issuedBooks = 0;
    try {
      const booksRow = db.prepare('SELECT COUNT(*) as count FROM books WHERE is_active = 1').get();
      totalBooks = booksRow ? booksRow.count : 0;
      const issuedRow = db.prepare("SELECT COUNT(*) as count FROM book_issues WHERE status = 'Issued'").get();
      issuedBooks = issuedRow ? issuedRow.count : 0;
    } catch (e) {}

    // 14. Total Exams
    let totalExams = 0;
    try {
      const examsRow = db.prepare('SELECT COUNT(*) as count FROM exams').get();
      totalExams = examsRow ? examsRow.count : 0;
    } catch (e) {}

    // 15. Total Courses / Subjects
    let totalCourses = 0;
    try {
      const coursesRow = db.prepare('SELECT COUNT(*) as count FROM courses WHERE is_active = 1').get();
      totalCourses = coursesRow ? coursesRow.count : 0;
    } catch (e) {}

    // 16. Total System Users
    let totalUsers = 0;
    try {
      const usersRow = db.prepare('SELECT COUNT(*) as count FROM users WHERE is_active = 1').get();
      totalUsers = usersRow ? usersRow.count : 0;
    } catch (e) {}

    // 17. New Admissions This Month
    let newAdmissionsThisMonth = 0;
    try {
      const currentMonth = new Date().toISOString().substring(0, 7);
      const admRow = db.prepare("SELECT COUNT(*) as count FROM students WHERE is_active = 1 AND admission_date LIKE ?").get(`${currentMonth}%`);
      newAdmissionsThisMonth = admRow ? admRow.count : 0;
    } catch (e) {}

    res.json({
      totalStudents,
      totalStaff,
      attendancePercentage,
      pendingFees,
      totalDonations,
      activeClasses,
      hostelOccupiedBeds,
      hostelTotalBeds,
      kitchenLowStock,
      generalLowStock,
      totalPurchases,
      totalSales,
      totalBooks,
      issuedBooks,
      totalExams,
      totalCourses,
      totalUsers,
      newAdmissionsThisMonth,
      recentActivity
    });
  } catch (error) {
    console.error('Dashboard Summary Error:', error);
    res.status(500).json({ error: error.message });
  }
};
