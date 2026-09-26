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

      // Determine proper conflict target for PostgreSQL ON CONFLICT clause
      let onConflict = 'id';
      if (table === 'role_permissions') {
        onConflict = 'role_id, permission_id';
      } else if (table === 'user_roles') {
        onConflict = 'user_id, role_id';
      } else if (table === 'settings') {
        onConflict = 'key';
      } else if (table === 'activity_logs') {
        onConflict = 'id';
      }

      const { data, error } = await supabase
        .from(table)
        .upsert(dataToSync, { onConflict });

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
   * Bulk Sync ALL SQLite Tables into Supabase PostgreSQL in batches
   */
  async syncAllFromSQLite(sqliteDb) {
    if (!supabase) return { error: 'Supabase not configured' };
    console.log('[Supabase] Starting full database sync from local SQLite...');

    // Fetch all tables that exist in local SQLite
    const allTables = sqliteDb.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name").all().map(t => t.name);

    const results = {};

    for (const table of allTables) {
      try {
        const rows = sqliteDb.prepare(`SELECT * FROM "${table}"`).all();
        if (rows && rows.length > 0) {
          const cleanedRows = rows.map(r => {
            const copy = { ...r };
            // Ensure null or empty values don't fail JSON serialisation
            return copy;
          });

          const batchSize = 100;
          let tableSuccess = true;
          let tableError = null;

          for (let i = 0; i < cleanedRows.length; i += batchSize) {
            const batch = cleanedRows.slice(i, i + batchSize);
            const res = await this.upsert(table, batch);
            if (res.error) {
              tableSuccess = false;
              tableError = res.error;
              break;
            }
          }

          results[table] = { count: rows.length, success: tableSuccess, error: tableError };
        } else {
          results[table] = { count: 0, success: true };
        }
      } catch (err) {
        results[table] = { count: 0, error: err.message };
      }
    }

    const totalSynced = Object.values(results).filter(r => r.success && r.count > 0).reduce((acc, r) => acc + r.count, 0);
    console.log(`[Supabase] Full sync completed: ${totalSynced} rows across tables.`);
    return results;
  },
};

module.exports = SupabaseService;
