const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

/**
 * @desc    Submit an online admission form
 * @route   POST /api/admissions
 * @access  Public
 */
exports.submitAdmission = (req, res) => {
  try {
    const { fullName, parentName, dob, gender, className, phone, address } = req.body;

    if (!fullName || !parentName || !dob || !gender || !className || !phone) {
      return res.status(400).json({ 
        message: 'Please provide all required fields' 
      });
    }

    const id = uuidv4();
    const stmt = db.prepare(`
      INSERT INTO admissions (id, full_name, parent_name, date_of_birth, gender, class_name, phone, address)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `);

    stmt.run(id, fullName, parentName, dob, gender, className, phone, address);

    res.status(201).json({
      success: true,
      message: 'Admission form submitted successfully',
      id
    });
  } catch (error) {
    console.error('Admission Submission Error:', error);
    res.status(500).json({ message: 'Server error during admission submission' });
  }
};

/**
 * @desc    Get all admissions (for admin)
 * @route   GET /api/admissions
 * @access  Private (Reports/Students view permission)
 */
exports.getAdmissions = (req, res) => {
  try {
    const admissions = db.prepare('SELECT * FROM admissions ORDER BY created_at DESC').all();
    res.json(admissions);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching admissions' });
  }
};
