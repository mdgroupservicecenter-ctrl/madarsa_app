const { db } = require('../config/database');
const { v4: uuidv4 } = require('uuid');

// ─── SETTINGS ────────────────────────────────────────────────────────
exports.getSettings = (req, res) => {
  try {
    const settings = db.prepare('SELECT * FROM library_settings WHERE id = ?').get('default');
    res.json(settings || {
      fine_per_day: 5.0,
      max_books_per_student: 3,
      default_due_days: 14,
      lost_book_fine: 500.0,
      lost_book_found_fine: 100.0
    });
  } catch (error) {
    res.status(500).json({ message: 'Error fetching library settings', error: error.message });
  }
};

exports.updateSettings = (req, res) => {
  try {
    const { fine_per_day, max_books_per_student, default_due_days, lost_book_fine, lost_book_found_fine } = req.body;

    db.prepare(`
      UPDATE library_settings 
      SET fine_per_day = ?, max_books_per_student = ?, default_due_days = ?, lost_book_fine = ?, lost_book_found_fine = ?, updated_at = datetime('now')
      WHERE id = 'default'
    `).run(
      Number(fine_per_day) || 0.0,
      parseInt(max_books_per_student) || 3,
      parseInt(default_due_days) || 14,
      Number(lost_book_fine) || 0.0,
      Number(lost_book_found_fine) || 0.0
    );

    res.json({ success: true, message: 'Library settings updated successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error updating library settings', error: error.message });
  }
};

// ─── CATEGORIES ──────────────────────────────────────────────────────
exports.getCategories = (req, res) => {
  try {
    const categories = db.prepare(`
      SELECT c.*, 
             (SELECT COUNT(*) FROM library_books WHERE category_id = c.id) AS book_count
      FROM library_categories c
      ORDER BY c.name ASC
    `).all();
    res.json(categories);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching categories', error: error.message });
  }
};

exports.createCategory = (req, res) => {
  try {
    const { name, description } = req.body;
    if (!name) {
      return res.status(400).json({ message: 'Category name is required' });
    }

    const id = uuidv4();
    db.prepare(`
      INSERT INTO library_categories (id, name, description)
      VALUES (?, ?, ?)
    `).run(id, String(name).trim(), description ? description.trim() : null);

    res.status(201).json({ success: true, message: 'Category created successfully', data: { id, name, description } });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ message: 'Category name already exists' });
    }
    res.status(500).json({ message: 'Error creating category', error: error.message });
  }
};

exports.updateCategory = (req, res) => {
  try {
    const { id } = req.params;
    const { name, description } = req.body;

    const existing = db.prepare('SELECT * FROM library_categories WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Category not found' });
    }

    db.prepare(`
      UPDATE library_categories
      SET name = ?, description = ?
      WHERE id = ?
    `).run(String(name).trim(), description ? description.trim() : null, id);

    res.json({ success: true, message: 'Category updated successfully' });
  } catch (error) {
    if (error.code === 'SQLITE_CONSTRAINT_UNIQUE') {
      return res.status(400).json({ message: 'Category name already exists' });
    }
    res.status(500).json({ message: 'Error updating category', error: error.message });
  }
};

exports.deleteCategory = (req, res) => {
  try {
    const { id } = req.params;

    // Check if books are assigned to this category
    const bookCount = db.prepare('SELECT COUNT(*) as count FROM library_books WHERE category_id = ?').get(id).count;
    if (bookCount > 0) {
      return res.status(400).json({ message: 'Cannot delete category containing books' });
    }

    db.prepare('DELETE FROM library_categories WHERE id = ?').run(id);
    res.json({ success: true, message: 'Category deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting category', error: error.message });
  }
};

// ─── BOOKS ───────────────────────────────────────────────────────────
exports.getBooks = (req, res) => {
  try {
    const { search, category_id, availability } = req.query;
    let queryStr = `
      SELECT b.*, c.name AS category_name
      FROM library_books b
      LEFT JOIN library_categories c ON b.category_id = c.id
      WHERE 1=1
    `;
    const params = [];

    if (search) {
      queryStr += ` AND (b.title LIKE ? OR b.author LIKE ? OR b.isbn LIKE ?)`;
      params.push(`%${search}%`, `%${search}%`, `%${search}%`);
    }

    if (category_id) {
      queryStr += ` AND b.category_id = ?`;
      params.push(category_id);
    }

    if (availability === 'available') {
      queryStr += ` AND b.available_copies > 0`;
    } else if (availability === 'out_of_stock') {
      queryStr += ` AND b.available_copies = 0`;
    }

    queryStr += ` ORDER BY b.title ASC`;

    const books = db.prepare(queryStr).all(...params);
    res.json(books);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching books', error: error.message });
  }
};

exports.createBook = (req, res) => {
  try {
    const { title, author, isbn, category_id, publisher, language, total_copies, shelf_location, description, default_due_days, lost_book_fine, lost_book_found_fine, fine_per_day } = req.body;
    if (!title) {
      return res.status(400).json({ message: 'Book title is required' });
    }

    const id = uuidv4();
    const copies = parseInt(total_copies) || 1;

    db.prepare(`
      INSERT INTO library_books (id, title, author, isbn, category_id, publisher, language, total_copies, available_copies, shelf_location, description, default_due_days, lost_book_fine, lost_book_found_fine, fine_per_day)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id,
      String(title).trim(),
      author ? author.trim() : null,
      isbn ? isbn.trim() : null,
      category_id || null,
      publisher ? publisher.trim() : null,
      language || 'Urdu',
      copies,
      copies, // Initially available_copies equals total_copies
      shelf_location ? shelf_location.trim() : null,
      description ? description.trim() : null,
      default_due_days ? parseInt(default_due_days) : null,
      lost_book_fine ? parseFloat(lost_book_fine) : null,
      lost_book_found_fine ? parseFloat(lost_book_found_fine) : null,
      fine_per_day ? parseFloat(fine_per_day) : null
    );

    res.status(201).json({ success: true, message: 'Book added successfully', data: { id, title } });
  } catch (error) {
    res.status(500).json({ message: 'Error adding book', error: error.message });
  }
};

exports.updateBook = (req, res) => {
  try {
    const { id } = req.params;
    const { title, author, isbn, category_id, publisher, language, total_copies, shelf_location, description, default_due_days, lost_book_fine, lost_book_found_fine, fine_per_day } = req.body;

    const existing = db.prepare('SELECT * FROM library_books WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ message: 'Book not found' });
    }

    const newTotal = parseInt(total_copies) || 1;
    const currentIssued = existing.total_copies - existing.available_copies;
    
    if (newTotal < currentIssued) {
      return res.status(400).json({ message: `Cannot set total copies lower than currently issued copies (${currentIssued})` });
    }

    const newAvailable = newTotal - currentIssued;

    db.prepare(`
      UPDATE library_books
      SET title = ?, author = ?, isbn = ?, category_id = ?, publisher = ?, language = ?, total_copies = ?, available_copies = ?, shelf_location = ?, description = ?, default_due_days = ?, lost_book_fine = ?, lost_book_found_fine = ?, fine_per_day = ?
      WHERE id = ?
    `).run(
      String(title).trim(),
      author ? author.trim() : null,
      isbn ? isbn.trim() : null,
      category_id || null,
      publisher ? publisher.trim() : null,
      language || 'Urdu',
      newTotal,
      newAvailable,
      shelf_location ? shelf_location.trim() : null,
      description ? description.trim() : null,
      default_due_days ? parseInt(default_due_days) : null,
      lost_book_fine ? parseFloat(lost_book_fine) : null,
      lost_book_found_fine ? parseFloat(lost_book_found_fine) : null,
      fine_per_day ? parseFloat(fine_per_day) : null,
      id
    );

    res.json({ success: true, message: 'Book updated successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error updating book', error: error.message });
  }
};

exports.deleteBook = (req, res) => {
  try {
    const { id } = req.params;

    // Check if book has active issues
    const activeIssues = db.prepare("SELECT COUNT(*) as count FROM library_transactions WHERE book_id = ? AND status IN ('Issued', 'Overdue')").get(id).count;
    if (activeIssues > 0) {
      return res.status(400).json({ message: 'Cannot delete book that is currently issued to students' });
    }

    db.prepare('DELETE FROM library_books WHERE id = ?').run(id);
    res.json({ success: true, message: 'Book deleted successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error deleting book', error: error.message });
  }
};

// ─── TRANSACTIONS ────────────────────────────────────────────────────
exports.getTransactions = (req, res) => {
  try {
    const { status, student_id, staff_id, book_id, start_date, end_date } = req.query;
    
    // First, let's fetch settings to ensure we calculate overdue status correctly
    const settings = db.prepare("SELECT * FROM library_settings WHERE id = 'default'").get();
    const finePerDay = settings ? settings.fine_per_day : 5.0;

    let queryStr = `
      SELECT t.*, 
             COALESCE(t.borrower_name, s.full_name, st.full_name) AS computed_borrower_name,
             COALESCE(t.hostel_name, 'No Hostel') AS computed_hostel_name,
             COALESCE(t.room_number, '-') AS computed_room_number,
             COALESCE(t.bed_number, '-') AS computed_bed_number,
             b.title AS book_title, b.author AS book_author,
             s.full_name AS student_name, s.father_name, s.surname, s.gr_no AS student_gr_no, s.village AS student_village,
             st.full_name AS staff_name, st.staff_no, st.mobile_no AS staff_mobile,
             CASE 
               WHEN t.status = 'Issued' AND date('now') > t.due_date THEN 'Overdue'
               ELSE t.status 
             END AS computed_status,
             CASE 
               WHEN t.status = 'Issued' AND date('now') > t.due_date 
               THEN CAST(julianday('now') - julianday(t.due_date) AS INTEGER) 
               ELSE 0 
             END AS overdue_days
      FROM library_transactions t
      JOIN library_books b ON t.book_id = b.id
      LEFT JOIN students s ON t.student_id = s.id
      LEFT JOIN staff st ON t.staff_id = st.id
      WHERE 1=1
    `;
    const params = [];

    if (student_id) {
      queryStr += ` AND t.student_id = ?`;
      params.push(student_id);
    }

    if (staff_id) {
      queryStr += ` AND t.staff_id = ?`;
      params.push(staff_id);
    }

    if (book_id) {
      queryStr += ` AND t.book_id = ?`;
      params.push(book_id);
    }

    if (start_date && end_date) {
      queryStr += ` AND t.issue_date BETWEEN ? AND ?`;
      params.push(start_date, end_date);
    }

    queryStr += ` ORDER BY t.created_at DESC`;

    const txs = db.prepare(queryStr).all(...params);

    // Filter by status on JavaScript side if filtered by computed status
    let filteredTxs = txs;
    if (status) {
      filteredTxs = txs.filter(tx => {
        if (status === 'Overdue') {
          return tx.computed_status === 'Overdue';
        } else if (status === 'Issued') {
          return tx.computed_status === 'Issued'; // active and NOT overdue
        } else {
          return tx.status === status;
        }
      });
    }

    // Map the fine dynamically if it's currently overdue and not returned yet
    const result = filteredTxs.map(tx => {
      let finalFine = tx.fine_amount || 0;
      if (tx.computed_status === 'Overdue') {
        const book = db.prepare("SELECT fine_per_day FROM library_books WHERE id = ?").get(tx.book_id);
        const bookFinePerDay = book && book.fine_per_day != null ? book.fine_per_day : finePerDay;
        finalFine = tx.overdue_days * bookFinePerDay;
      }
      return {
        ...tx,
        fine_amount: finalFine
      };
    });

    res.json(result);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching transactions', error: error.message });
  }
};

exports.issueBook = (req, res) => {
  const transaction = db.transaction((body, user) => {
    const { student_id, staff_id, borrower_name, hostel_name, room_number, bed_number, book_id, due_date } = body;
    if (!student_id && !staff_id) {
      throw new Error('Student or Staff selection is required');
    }
    if (!book_id) {
      throw new Error('Book ID is required');
    }

    // 1. Get Library settings
    const settings = db.prepare("SELECT * FROM library_settings WHERE id = 'default'").get();
    const maxBooks = settings ? settings.max_books_per_student : 3;
    const defaultDays = settings ? settings.default_due_days : 14;

    // 2. Check student/staff current active issues & duplicates
    if (student_id) {
      const activeCount = db.prepare(`
        SELECT COUNT(*) as count 
        FROM library_transactions 
        WHERE student_id = ? AND status IN ('Issued', 'Overdue')
      `).get(student_id).count;

      if (activeCount >= maxBooks) {
        throw new Error(`Student has already reached the maximum issue limit of ${maxBooks} books.`);
      }

      const duplicateCount = db.prepare(`
        SELECT COUNT(*) as count
        FROM library_transactions
        WHERE student_id = ? AND book_id = ? AND status IN ('Issued', 'Overdue')
      `).get(student_id, book_id).count;

      if (duplicateCount > 0) {
        throw new Error('This book is already currently issued to this student.');
      }
    } else if (staff_id) {
      const duplicateCount = db.prepare(`
        SELECT COUNT(*) as count
        FROM library_transactions
        WHERE staff_id = ? AND book_id = ? AND status IN ('Issued', 'Overdue')
      `).get(staff_id, book_id).count;

      if (duplicateCount > 0) {
        throw new Error('This book is already currently issued to this staff member.');
      }
    }

    // 4. Check book availability
    const book = db.prepare('SELECT available_copies, total_copies FROM library_books WHERE id = ?').get(book_id);
    if (!book) {
      throw new Error('Book not found.');
    }
    if (book.available_copies <= 0) {
      throw new Error('No copies of this book are currently available.');
    }

    // 5. Calculate dates
    const today = new Date().toISOString().split('T')[0];
    let finalDueDate = due_date;
    if (!finalDueDate) {
      const d = new Date();
      d.setDate(d.getDate() + defaultDays);
      finalDueDate = d.toISOString().split('T')[0];
    }

    // 6. Create Transaction
    const id = body.id || uuidv4();
    db.prepare(`
      INSERT INTO library_transactions (
        id, book_id, student_id, staff_id, borrower_name, hostel_name, room_number, bed_number, issue_date, due_date, status, issued_by
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Issued', ?)
    `).run(
      id,
      book_id,
      student_id || null,
      staff_id || null,
      borrower_name || null,
      hostel_name || null,
      room_number || null,
      bed_number || null,
      today,
      finalDueDate,
      user || 'Admin'
    );

    // 7. Decrement available copies
    db.prepare(`
      UPDATE library_books
      SET available_copies = available_copies - 1
      WHERE id = ?
    `).run(book_id);

    return { id, issue_date: today, due_date: finalDueDate };
  });

  try {
    const result = transaction(req.body, req.user ? req.user.username : 'Admin');
    res.status(201).json({ success: true, message: 'Book issued successfully', data: result });
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

exports.returnBook = (req, res) => {
  const transaction = db.transaction((id, remarks, custom_fine) => {
    const tx = db.prepare('SELECT * FROM library_transactions WHERE id = ?').get(id);
    if (!tx) {
      throw new Error('Transaction record not found.');
    }
    if (tx.status === 'Returned') {
      throw new Error('Book has already been returned.');
    }

    // 1. Calculate Fine
    const todayStr = new Date().toISOString().split('T')[0];
    let finalFine = 0;
    
    if (custom_fine !== undefined && custom_fine !== null) {
      finalFine = parseFloat(custom_fine);
    } else if (todayStr > tx.due_date && tx.status !== 'Lost') {
      const settings = db.prepare("SELECT * FROM library_settings WHERE id = 'default'").get();
      const finePerDay = settings ? settings.fine_per_day : 5.0;
      
      // Check if the book itself has a custom fine_per_day
      const book = db.prepare("SELECT fine_per_day FROM library_books WHERE id = ?").get(tx.book_id);
      const bookFinePerDay = book && book.fine_per_day != null ? book.fine_per_day : finePerDay;

      const due = new Date(tx.due_date);
      const today = new Date(todayStr);
      const diffTime = Math.abs(today - due);
      const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
      
      finalFine = diffDays * bookFinePerDay;
    } else if (tx.status === 'Lost') {
      // Default to the lost_book_found_fine setting or book specific setting
      const settings = db.prepare("SELECT * FROM library_settings WHERE id = 'default'").get();
      const defaultFoundFine = settings ? (settings.lost_book_found_fine || 100.0) : 100.0;
      
      const book = db.prepare("SELECT lost_book_found_fine FROM library_books WHERE id = ?").get(tx.book_id);
      finalFine = book && book.lost_book_found_fine != null ? book.lost_book_found_fine : defaultFoundFine;
    }

    // 2. Update transaction
    db.prepare(`
      UPDATE library_transactions
      SET return_date = ?, status = 'Returned', fine_amount = ?, remarks = ?
      WHERE id = ?
    `).run(todayStr, finalFine, remarks || null, id);

    // 3. Increment book availability
    if (tx.status === 'Lost') {
      db.prepare(`
        UPDATE library_books
        SET total_copies = total_copies + 1,
            available_copies = MIN(total_copies + 1, available_copies + 1)
        WHERE id = ?
      `).run(tx.book_id);
    } else {
      db.prepare(`
        UPDATE library_books
        SET available_copies = MIN(total_copies, available_copies + 1)
        WHERE id = ?
      `).run(tx.book_id);
    }

    return { fine_amount: finalFine, return_date: todayStr };
  });

  try {
    const { id } = req.params;
    const { remarks, custom_fine } = req.body;
    const result = transaction(id, remarks, custom_fine);
    res.json({ success: true, message: 'Book returned successfully', data: result });
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

exports.markBookLost = (req, res) => {
  const transaction = db.transaction((id, remarks) => {
    const tx = db.prepare('SELECT * FROM library_transactions WHERE id = ?').get(id);
    if (!tx) {
      throw new Error('Transaction record not found.');
    }
    if (tx.status === 'Returned') {
      throw new Error('Cannot mark returned book as lost.');
    }
    if (tx.status === 'Lost') {
      throw new Error('Book is already marked as lost.');
    }

    const settings = db.prepare("SELECT * FROM library_settings WHERE id = 'default'").get();
    const lostFine = settings ? settings.lost_book_fine : 500.0;

    // 1. Update Transaction to Lost
    db.prepare(`
      UPDATE library_transactions
      SET status = 'Lost', fine_amount = ?, remarks = ?
      WHERE id = ?
    `).run(lostFine, remarks || 'Book marked as lost by administrator', id);

    // 2. Decrement total copies and DO NOT increment available copies since it is lost!
    // Since available copies was already decremented on issue, it should remain decremented.
    // Total copies must be decremented by 1 to reflect that the physical book is gone.
    db.prepare(`
      UPDATE library_books
      SET total_copies = MAX(0, total_copies - 1)
      WHERE id = ?
    `).run(tx.book_id);

    return { lost_fine: lostFine };
  });

  try {
    const { id } = req.params;
    const { remarks } = req.body;
    const result = transaction(id, remarks);
    res.json({ success: true, message: 'Book marked as lost successfully', data: result });
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

exports.deleteTransaction = (req, res) => {
  const transaction = db.transaction((id) => {
    const tx = db.prepare('SELECT * FROM library_transactions WHERE id = ?').get(id);
    if (!tx) {
      throw new Error('Transaction record not found.');
    }

    // If active or lost, we must restore copies first
    if (tx.status === 'Issued' || tx.status === 'Overdue') {
      db.prepare(`
        UPDATE library_books
        SET available_copies = MIN(total_copies, available_copies + 1)
        WHERE id = ?
      `).run(tx.book_id);
    } else if (tx.status === 'Lost') {
      db.prepare(`
        UPDATE library_books
        SET total_copies = total_copies + 1,
            available_copies = MIN(total_copies + 1, available_copies + 1)
        WHERE id = ?
      `).run(tx.book_id);
    }

    db.prepare('DELETE FROM library_transactions WHERE id = ?').run(id);
  });

  try {
    const { id } = req.params;
    transaction(id);
    res.json({ success: true, message: 'Transaction deleted successfully' });
  } catch (error) {
    res.status(400).json({ message: error.message });
  }
};

// ─── STATS & HISTORY ─────────────────────────────────────────────────
exports.getStats = (req, res) => {
  try {
    const totalBooks = db.prepare('SELECT COUNT(*) as count FROM library_books').get().count;
    const totalCopies = db.prepare('SELECT SUM(total_copies) as count FROM library_books').get().count || 0;
    const availableCopies = db.prepare('SELECT SUM(available_copies) as count FROM library_books').get().count || 0;

    // Active issues and overdue count
    const transactions = db.prepare(`
      SELECT status, due_date
      FROM library_transactions
      WHERE status IN ('Issued', 'Overdue')
    `).all();

    const todayStr = new Date().toISOString().split('T')[0];
    let issuedCount = 0;
    let overdueCount = 0;

    transactions.forEach(t => {
      if (t.status === 'Issued' && todayStr > t.due_date) {
        overdueCount++;
      } else if (t.status === 'Issued') {
        issuedCount++;
      } else if (t.status === 'Overdue') {
        overdueCount++;
      }
    });

    const lostCount = db.prepare("SELECT COUNT(*) as count FROM library_transactions WHERE status = 'Lost'").get().count;
    
    const today = new Date().toISOString().split('T')[0];
    const returnedToday = db.prepare("SELECT COUNT(*) as count FROM library_transactions WHERE status = 'Returned' AND return_date = ?").get(today).count;
    const totalFines = db.prepare("SELECT SUM(fine_amount) as total FROM library_transactions").get().total || 0;

    // Category breakdown
    const categoryBreakdown = db.prepare(`
      SELECT c.name, COUNT(b.id) as count
      FROM library_categories c
      LEFT JOIN library_books b ON b.category_id = c.id
      GROUP BY c.id
      ORDER BY count DESC
    `).all();

    res.json({
      totalBooks,
      totalCopies,
      availableCopies,
      issuedCount,
      overdueCount,
      lostCount,
      returnedToday,
      totalFinesCollected: totalFines,
      categoryBreakdown
    });
  } catch (error) {
    res.status(500).json({ message: 'Error fetching stats', error: error.message });
  }
};

exports.getStudentHistory = (req, res) => {
  try {
    const { studentId } = req.params;

    const history = db.prepare(`
      SELECT t.*, b.title AS book_title, b.author AS book_author,
             CASE 
               WHEN t.status = 'Issued' AND date('now') > t.due_date THEN 'Overdue'
               ELSE t.status 
             END AS computed_status
      FROM library_transactions t
      JOIN library_books b ON t.book_id = b.id
      WHERE t.student_id = ?
      ORDER BY t.created_at DESC
    `).all(studentId);

    res.json(history);
  } catch (error) {
    res.status(500).json({ message: 'Error fetching student borrowing history', error: error.message });
  }
};

exports.updateTransaction = (req, res) => {
  const transaction = db.transaction((id, body) => {
    const { due_date, remarks, status, fine_amount } = body;

    const existing = db.prepare('SELECT * FROM library_transactions WHERE id = ?').get(id);
    if (!existing) {
      throw new Error('Transaction record not found.');
    }

    const newStatus = status || existing.status;
    const oldStatus = existing.status;

    // Adjust copies if status is changing
    if (newStatus !== oldStatus) {
      // 1. Revert effect of oldStatus on book copies
      if (oldStatus === 'Issued' || oldStatus === 'Overdue') {
        // Increment availability since the issue is no longer active under this transaction
        db.prepare(`
          UPDATE library_books
          SET available_copies = MIN(total_copies, available_copies + 1)
          WHERE id = ?
        `).run(existing.book_id);
      } else if (oldStatus === 'Lost') {
        // Since book was lost, total_copies was decremented. Restore it now.
        db.prepare(`
          UPDATE library_books
          SET total_copies = total_copies + 1,
              available_copies = MIN(total_copies + 1, available_copies + 1)
          WHERE id = ?
        `).run(existing.book_id);
      }

      // 2. Apply effect of newStatus on book copies
      if (newStatus === 'Issued' || newStatus === 'Overdue') {
        // Check availability
        const book = db.prepare('SELECT available_copies FROM library_books WHERE id = ?').get(existing.book_id);
        if (book.available_copies <= 0) {
          throw new Error('No available copies left to mark this book as active.');
        }
        db.prepare(`
          UPDATE library_books
          SET available_copies = MAX(0, available_copies - 1)
          WHERE id = ?
        `).run(existing.book_id);
      } else if (newStatus === 'Lost') {
        db.prepare(`
          UPDATE library_books
          SET total_copies = MAX(0, total_copies - 1)
          WHERE id = ?
        `).run(existing.book_id);
      }
    }

    let finalFine = fine_amount !== undefined ? Number(fine_amount) : existing.fine_amount;

    // Automatically apply lost book found fine if status changed from Lost to Returned
    if (oldStatus === 'Lost' && newStatus === 'Returned') {
      const isCustomFinePassed = fine_amount !== undefined && Number(fine_amount) !== existing.fine_amount;
      if (!isCustomFinePassed) {
        const settings = db.prepare("SELECT * FROM library_settings WHERE id = 'default'").get();
        const defaultFoundFine = settings ? (settings.lost_book_found_fine || 100.0) : 100.0;
        
        const book = db.prepare("SELECT lost_book_found_fine FROM library_books WHERE id = ?").get(existing.book_id);
        finalFine = book && book.lost_book_found_fine != null ? book.lost_book_found_fine : defaultFoundFine;
      }
    }

    // Update transaction
    db.prepare(`
      UPDATE library_transactions
      SET due_date = ?, remarks = ?, status = ?, fine_amount = ?
      WHERE id = ?
    `).run(
      due_date || existing.due_date,
      remarks !== undefined ? remarks : existing.remarks,
      newStatus,
      finalFine,
      id
    );
  });

  try {
    const { id } = req.params;
    transaction(id, req.body);
    res.json({ success: true, message: 'Transaction updated successfully' });
  } catch (error) {
    res.status(500).json({ message: 'Error updating transaction', error: error.message });
  }
};
