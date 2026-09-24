const API_KEY = process.env.FIREBASE_API_KEY || 'AIzaSyBQINwAJ1VjWbI6_UsEE_Mq-97VsP_jH3A';
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'madarsa-management-cloud';
const FIRESTORE_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

/**
 * Convert standard JS Object to Firestore format
 */
function toFirestoreFields(obj) {
  if (!obj || typeof obj !== 'object') return {};
  const fields = {};
  for (const [key, val] of Object.entries(obj)) {
    if (val === null || val === undefined) {
      fields[key] = { nullValue: null };
    } else if (typeof val === 'boolean') {
      fields[key] = { booleanValue: val };
    } else if (typeof val === 'number') {
      if (Number.isInteger(val)) {
        fields[key] = { integerValue: val.toString() };
      } else {
        fields[key] = { doubleValue: val };
      }
    } else if (typeof val === 'string') {
      fields[key] = { stringValue: val };
    } else if (Array.isArray(val)) {
      fields[key] = {
        arrayValue: {
          values: val.map((v) => {
            if (typeof v === 'string') return { stringValue: v };
            if (typeof v === 'number') return { integerValue: v.toString() };
            if (typeof v === 'boolean') return { booleanValue: v };
            return { stringValue: String(v) };
          })
        }
      };
    } else if (typeof val === 'object') {
      fields[key] = { mapValue: { fields: toFirestoreFields(val) } };
    }
  }
  return fields;
}

/**
 * Convert Firestore JSON fields to standard JS Object
 */
function fromFirestoreFields(fields) {
  if (!fields) return {};
  const obj = {};
  for (const [key, field] of Object.entries(fields)) {
    if ('stringValue' in field) obj[key] = field.stringValue;
    else if ('integerValue' in field) obj[key] = parseInt(field.integerValue, 10);
    else if ('doubleValue' in field) obj[key] = parseFloat(field.doubleValue);
    else if ('booleanValue' in field) obj[key] = field.booleanValue;
    else if ('nullValue' in field) obj[key] = null;
    else if ('arrayValue' in field) {
      obj[key] = (field.arrayValue.values || []).map((v) => {
        if ('stringValue' in v) return v.stringValue;
        if ('integerValue' in v) return parseInt(v.integerValue, 10);
        if ('doubleValue' in v) return parseFloat(v.doubleValue);
        if ('booleanValue' in v) return v.booleanValue;
        return null;
      });
    } else if ('mapValue' in field) {
      obj[key] = fromFirestoreFields(field.mapValue.fields);
    }
  }
  return obj;
}

const FirebaseService = {
  /**
   * Save or Update a Document in Firestore
   */
  async setDocument(collection, docId, data) {
    try {
      const cleanId = String(docId).replace(/[^a-zA-Z0-9_-]/g, '_');
      const url = `${FIRESTORE_BASE}/${collection}/${cleanId}?key=${API_KEY}`;
      const res = await fetch(url, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fields: toFirestoreFields(data) })
      });
      return res.ok;
    } catch (err) {
      console.error(`Firebase setDocument error (${collection}/${docId}):`, err.message);
      return false;
    }
  },

  /**
   * Get a Document from Firestore
   */
  async getDocument(collection, docId) {
    try {
      const cleanId = String(docId).replace(/[^a-zA-Z0-9_-]/g, '_');
      const url = `${FIRESTORE_BASE}/${collection}/${cleanId}?key=${API_KEY}`;
      const res = await fetch(url);
      if (!res.ok) return null;
      const json = await res.json();
      const obj = fromFirestoreFields(json.fields);
      obj.id = docId;
      return obj;
    } catch (err) {
      console.error(`Firebase getDocument error (${collection}/${docId}):`, err.message);
      return null;
    }
  },

  /**
   * Delete a Document from Firestore
   */
  async deleteDocument(collection, docId) {
    try {
      const cleanId = String(docId).replace(/[^a-zA-Z0-9_-]/g, '_');
      const url = `${FIRESTORE_BASE}/${collection}/${cleanId}?key=${API_KEY}`;
      const res = await fetch(url, { method: 'DELETE' });
      return res.ok;
    } catch (err) {
      console.error(`Firebase deleteDocument error (${collection}/${docId}):`, err.message);
      return false;
    }
  },

  /**
   * Query all documents in a collection
   */
  async getCollection(collection) {
    try {
      const url = `${FIRESTORE_BASE}/${collection}?key=${API_KEY}`;
      const res = await fetch(url);
      if (!res.ok) return [];
      const json = await res.json();
      if (!json.documents || !Array.isArray(json.documents)) return [];
      return json.documents.map((doc) => {
        const obj = fromFirestoreFields(doc.fields);
        obj.id = doc.name ? doc.name.split('/').pop() : '';
        return obj;
      });
    } catch (err) {
      console.error(`Firebase getCollection error (${collection}):`, err.message);
      return [];
    }
  },

  /**
   * Sync Trial Telemetry to Firestore
   */
  async syncTrialPing(hwid, deviceData) {
    return this.setDocument('trial_devices', hwid, {
      ...deviceData,
      last_heartbeat_at: new Date().toISOString()
    });
  },

  /**
   * Sync Customer License to Firestore
   */
  async syncLicense(licenseKey, licenseData) {
    return this.setDocument('licenses', licenseKey, licenseData);
  },

  /**
   * Sync a Student Record to Firestore
   */
  async syncStudent(student) {
    if (!student || !student.id) return;
    return this.setDocument('students', student.id, student);
  },

  /**
   * Sync a Staff Record to Firestore
   */
  async syncStaff(staffMember) {
    if (!staffMember || !staffMember.id) return;
    return this.setDocument('staff', staffMember.id, staffMember);
  },

  /**
   * Sync a Fee Record to Firestore
   */
  async syncFee(fee) {
    if (!fee || !fee.id) return;
    return this.setDocument('fees', fee.id, fee);
  },

  /**
   * Full Database Sync from Local SQLite to Firebase
   */
  async syncAllToFirebase(db) {
    try {
      console.log('🔄 Starting Fast Sync with Google Firebase Cloud...');
      // 1. Sync Students
      const students = db.prepare('SELECT * FROM students LIMIT 10').all();
      for (const s of students) {
        await this.syncStudent(s);
      }
      console.log(`✅ Synced ${students.length} students to Firebase.`);

      // 2. Sync Staff
      const staffList = db.prepare('SELECT * FROM staff LIMIT 10').all();
      for (const st of staffList) {
        await this.syncStaff(st);
      }
      console.log(`✅ Synced ${staffList.length} staff to Firebase.`);

      // 3. Sync Licenses
      const licenses = db.prepare('SELECT * FROM licenses').all();
      for (const lic of licenses) {
        await this.syncLicense(lic.license_key, lic);
      }
      console.log(`✅ Synced ${licenses.length} licenses to Firebase.`);

      return {
        success: true,
        studentsCount: students.length,
        staffCount: staffList.length,
        licensesCount: licenses.length
      };
    } catch (err) {
      console.error('Firebase Full Sync error:', err);
      return { success: false, error: err.message };
    }
  }
};

module.exports = FirebaseService;
