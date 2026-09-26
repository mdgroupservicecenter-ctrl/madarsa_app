const { createClient } = require('@supabase/supabase-js');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });

const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SUPABASE_KEY = process.env.SUPABASE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY || '';

let supabase = null;

if (SUPABASE_URL && SUPABASE_KEY) {
  try {
    supabase = createClient(SUPABASE_URL, SUPABASE_KEY, {
      auth: { persistSession: false },
    });
    console.log('[Supabase] Client initialized successfully for:', SUPABASE_URL);
  } catch (err) {
    console.error('[Supabase] Initialization error:', err.message);
  }
} else {
  console.log('[Supabase] Credentials not set in .env yet. Running in offline/local-first mode.');
}

const SupabaseService = {
  getClient() {
    return supabase;
  },

  isConfigured() {
    return !!supabase;
  },

  /**
   * Generic UPSERT into any Supabase PostgreSQL table
   */
  async upsert(table, records) {
    if (!supabase) return { error: 'Supabase not configured' };
    try {
      const dataToSync = Array.isArray(records) ? records : [records];
      if (dataToSync.length === 0) return { success: true };

      const { data, error } = await supabase
        .from(table)
        .upsert(dataToSync, { onConflict: 'id' });

      if (error) {
        console.error(`[Supabase Sync Error] ${table}:`, error.message);
        return { error: error.message };
      }
      return { success: true, data };
    } catch (e) {
      console.error(`[Supabase Exception] ${table}:`, e.message);
      return { error: e.message };
    }
  },

  /**
   * Delete record by ID from table
   */
  async deleteRecord(table, id) {
    if (!supabase) return { error: 'Supabase not configured' };
    try {
      const { error } = await supabase.from(table).delete().eq('id', id);
      if (error) {
        console.error(`[Supabase Delete Error] ${table}:`, error.message);
        return { error: error.message };
      }
      return { success: true };
    } catch (e) {
      return { error: e.message };
    }
  },

  // ── Specific Module Sync Helpers ──

  async syncStudent(studentData) {
    return this.upsert('students', studentData);
  },

  async syncStaff(staffData) {
    return this.upsert('staff', staffData);
  },

  async syncAttendance(attendanceData) {
    return this.upsert('attendance', attendanceData);
  },

  async syncFee(feeData) {
    return this.upsert('fees', feeData);
  },

  async syncLicense(licenseData) {
    return this.upsert('licenses', licenseData);
  },

  /**
   * Bulk Sync All SQLite Tables into Supabase PostgreSQL in 1 go
   */
  async syncAllFromSQLite(sqliteDb) {
    if (!supabase) return { error: 'Supabase not configured' };
    console.log('[Supabase] Starting full database sync from local SQLite...');

    const tables = [
      'users',
      'roles',
      'departments',
      'classes',
      'courses',
      'books',
      'students',
      'staff',
      'staff_types',
      'qualifications',
      'attendance',
      'fees',
      'fee_types',
      'contributors',
      'donations',
      'hostels',
      'hostel_rooms',
      'kitchen_stock',
      'library_books',
      'exams',
      'academic_years',
      'licenses',
    ];

    const results = {};

    for (const table of tables) {
      try {
        const rows = sqliteDb.prepare(`SELECT * FROM ${table}`).all();
        if (rows && rows.length > 0) {
          const res = await this.upsert(table, rows);
          results[table] = { count: rows.length, success: !res.error };
        } else {
          results[table] = { count: 0, success: true };
        }
      } catch (err) {
        // Table might not exist in SQLite
        results[table] = { count: 0, error: err.message };
      }
    }

    console.log('[Supabase] Full sync completed:', results);
    return results;
  },
};

module.exports = SupabaseService;
