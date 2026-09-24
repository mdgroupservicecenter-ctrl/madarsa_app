const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');
const { db } = require('../config/database');
const { FEATURE_CATALOG, getAllFeatureIds } = require('../config/featureCatalog');
const FirebaseService = require('../services/firebaseService');
const getDb = () => db;

const SECRET_MASTER_KEY = 'MD_GROUP_MADARSA_ERP_MASTER_SECRET_2026_!#78692';

/**
 * Generate cryptographically signed license key
 */
function generateKeyString(institutionName, tier, validityDays, maxStudents, customModules = null) {
  const now = new Date();
  let expiry = null;
  if (tier !== 'lifetime' && validityDays && validityDays > 0) {
    expiry = new Date(now.getTime() + validityDays * 24 * 60 * 60 * 1000);
  }

  const payloadMap = {
    org: institutionName.trim(),
    tier: tier.toLowerCase(),
    iat: now.toISOString().split('T')[0],
    exp: expiry ? expiry.toISOString().split('T')[0] : 'lifetime',
    max: maxStudents || 0,
    uid: crypto.randomBytes(3).toString('hex').toUpperCase(),
    ...(customModules && customModules.length > 0 ? { mod: customModules } : {}),
  };

  const jsonString = JSON.stringify(payloadMap);
  const base64Payload = Buffer.from(jsonString).toString('base64url').replace(/=/g, '');

  const hmac = crypto.createHmac('sha256', SECRET_MASTER_KEY);
  hmac.update(base64Payload);
  const signature = hmac.digest('hex').substring(0, 16).toUpperCase();

  return `MDL-${tier.toUpperCase()}-${base64Payload}-${signature}`;
}

/**
 * Seller / Admin: Create a new Customer License Key (from Plan Template or Custom Features)
 */
exports.createLicense = async (req, res) => {
  try {
    const db = getDb();
    let {
      customer_name,
      institution_name,
      phone,
      email,
      plan_id,
      tier = 'pro',
      custom_modules = [],
      validity_days = 365,
      max_devices = 1,
      max_students = 0,
      price = 0,
      notes = '',
    } = req.body;

    if (!institution_name || !customer_name) {
      return res.status(400).json({ error: 'Customer Name and Madarsa Name are required' });
    }

    // If plan_id is given, load attributes from subscription_plans table
    if (plan_id) {
      const plan = db.prepare('SELECT * FROM subscription_plans WHERE id = ? OR plan_code = ?').get(plan_id, plan_id);
      if (plan) {
        tier = plan.plan_code;
        try {
          if (!custom_modules || custom_modules.length === 0) {
            custom_modules = JSON.parse(plan.features_json || '[]');
          }
        } catch (_) {}
        if (!validity_days || validity_days === 365) validity_days = plan.validity_days;
        if (!max_devices || max_devices === 1) max_devices = plan.max_devices;
        if (!price || price === 0) price = plan.price;
      }
    }

    const licenseId = uuidv4();
    const isLifetime = tier.toLowerCase() === 'lifetime' || validity_days === null || validity_days <= 0;
    const now = new Date();
    const issuedAt = now.toISOString();
    const expiresAt = isLifetime
        ? null
        : new Date(now.getTime() + parseInt(validity_days, 10) * 24 * 60 * 60 * 1000).toISOString();

    let modulesJson = null;
    if (Array.isArray(custom_modules) && custom_modules.length > 0) {
      const plan = db.prepare('SELECT * FROM subscription_plans WHERE plan_code = ? OR id = ?').get(tier.toLowerCase(), tier.toLowerCase());
      const planFeatures = plan && plan.features_json ? JSON.parse(plan.features_json) : [];
      const sortedCustom = [...custom_modules].sort();
      const sortedPlan = [...planFeatures].sort();
      if (JSON.stringify(sortedCustom) !== JSON.stringify(sortedPlan)) {
        modulesJson = JSON.stringify(custom_modules);
      }
    }

    const licenseKey = generateKeyString(
      institution_name,
      tier,
      isLifetime ? null : parseInt(validity_days, 10),
      parseInt(max_students, 10) || 0,
      custom_modules
    );

    const stmt = db.prepare(`
      INSERT INTO licenses (
        id, license_key, customer_name, institution_name, phone, email,
        tier, custom_modules, max_devices, max_students, issued_at, expires_at, price, status, notes
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?)
    `);

    stmt.run(
      licenseId,
      licenseKey,
      customer_name.trim(),
      institution_name.trim(),
      phone || '',
      email || '',
      tier.toLowerCase(),
      modulesJson,
      parseInt(max_devices, 10) || 1,
      parseInt(max_students, 10) || 0,
      issuedAt,
      expiresAt,
      parseFloat(price) || 0,
      notes || ''
    );

    // Log event
    db.prepare(`
      INSERT INTO license_logs (id, license_id, event_type, details, ip_address)
      VALUES (?, ?, 'created', ?, ?)
    `).run(uuidv4(), licenseId, `Created ${tier} plan for ${institution_name}`, req.ip);

    const created = db.prepare('SELECT * FROM licenses WHERE id = ?').get(licenseId);
    if (created) {
      FirebaseService.syncLicense(created.license_key, created).catch(console.error);
    }
    res.status(201).json({
      message: 'License key created successfully',
      license: created,
    });
  } catch (error) {
    console.error('Error creating license:', error);
    res.status(500).json({ error: error.message || 'Failed to create license' });
  }
};

/**
 * Seller / Admin: Get all licenses with registered devices and summary stats
 */
exports.getAllLicenses = async (req, res) => {
  try {
    const db = getDb();
    const licenses = db.prepare(`
      SELECT l.*, 
        (SELECT COUNT(*) FROM license_devices d WHERE d.license_id = l.id) AS device_count
      FROM licenses l
      ORDER BY l.created_at DESC
    `).all();

    // Attach devices to each license
    const devicesStmt = db.prepare('SELECT * FROM license_devices WHERE license_id = ? ORDER BY last_heartbeat_at DESC');
    const enriched = licenses.map((l) => {
      const devices = devicesStmt.all(l.id);
      return {
        ...l,
        devices,
      };
    });

    // Calculate Summary Statistics
    let totalRevenue = 0;
    let activeCount = 0;
    let expiredCount = 0;
    let revokedCount = 0;
    let totalDevices = 0;

    const now = new Date();
    enriched.forEach((l) => {
      totalRevenue += l.price || 0;
      totalDevices += l.devices.length;
      if (l.status === 'revoked') {
        revokedCount++;
      } else if (l.expires_at && new Date(l.expires_at) < now && l.tier !== 'lifetime') {
        expiredCount++;
      } else {
        activeCount++;
      }
    });

    res.json({
      stats: {
        total_licenses: enriched.length,
        active_licenses: activeCount,
        expired_licenses: expiredCount,
        revoked_licenses: revokedCount,
        total_registered_pcs: totalDevices,
        total_revenue: totalRevenue,
      },
      licenses: enriched,
    });
  } catch (error) {
    console.error('Error fetching licenses:', error);
    res.status(500).json({ error: error.message || 'Failed to fetch licenses' });
  }
};

/**
 * Seller / Admin: 1-Click Remote Kill-Switch (Block or Unblock a customer)
 */
exports.toggleLicenseBlock = async (req, res) => {
  try {
    const db = getDb();
    const { licenseId, status } = req.body; // status: 'active' | 'revoked'

    if (!licenseId || !status) {
      return res.status(400).json({ error: 'License ID and status are required' });
    }

    db.prepare('UPDATE licenses SET status = ?, updated_at = datetime(\'now\') WHERE id = ?').run(status, licenseId);

    const lic = db.prepare('SELECT * FROM licenses WHERE id = ?').get(licenseId);
    if (lic && lic.license_key) {
      try {
        await FirebaseService.setDocument('licenses', lic.license_key, {
          is_blocked: status === 'revoked',
          status: status,
          updated_at: new Date().toISOString(),
        });
      } catch (fbErr) {
        console.error('Firebase error in toggleLicenseBlock:', fbErr.message);
      }
    }

    db.prepare(`
      INSERT INTO license_logs (id, license_id, event_type, details, ip_address)
      VALUES (?, ?, 'status_change', ?, ?)
    `).run(uuidv4(), licenseId, `License status changed to ${status}`, req.ip);

    res.json({ message: `License status updated to ${status}` });
  } catch (error) {
    console.error('Error updating license status:', error);
    res.status(500).json({ error: error.message || 'Failed to update status' });
  }
};

/**
 * Seller / Admin: Update allowed modules / features for an existing customer license (Apply or Deny features)
 */
exports.updateLicensePermissions = async (req, res) => {
  try {
    const db = getDb();
    const { licenseId } = req.params;
    const { allowed_modules } = req.body;

    if (!licenseId || !Array.isArray(allowed_modules)) {
      return res.status(400).json({ error: 'License ID and allowed_modules array are required' });
    }

    const license = db.prepare('SELECT * FROM licenses WHERE id = ?').get(licenseId);
    if (!license) {
      return res.status(404).json({ error: 'License not found' });
    }

    const modulesJson = JSON.stringify(allowed_modules);
    db.prepare("UPDATE licenses SET custom_modules = ?, updated_at = datetime('now') WHERE id = ?").run(modulesJson, licenseId);

    try {
      if (license.license_key) {
        await FirebaseService.setDocument('licenses', license.license_key, {
          allowed_modules: allowed_modules,
          updated_at: new Date().toISOString(),
        });
      }
    } catch (fbErr) {
      console.error('Firebase error in updateLicensePermissions:', fbErr.message);
    }

    db.prepare(`
      INSERT INTO license_logs (id, license_id, event_type, details, ip_address)
      VALUES (?, ?, 'permissions_update', ?, ?)
    `).run(uuidv4(), licenseId, `Permissions updated: ${allowed_modules.length} modules`, req.ip);

    res.json({ message: 'License permissions updated successfully', allowed_modules });
  } catch (error) {
    console.error('Error updating permissions:', error);
    res.status(500).json({ error: error.message });
  }
};

/**
 * Seller / Admin: Unbind / Release a PC from a license
 */
exports.unbindDevice = async (req, res) => {
  try {
    const db = getDb();
    const { licenseId, deviceId } = req.body;

    if (!licenseId || !deviceId) {
      return res.status(400).json({ error: 'License ID and Device ID are required' });
    }

    const device = db.prepare('SELECT * FROM license_devices WHERE id = ? AND license_id = ?').get(deviceId, licenseId);
    if (!device) {
      return res.status(404).json({ error: 'Device not found on this license' });
    }

    db.prepare('DELETE FROM license_devices WHERE id = ?').run(deviceId);

    db.prepare(`
      INSERT INTO license_logs (id, license_id, hwid, event_type, details, ip_address)
      VALUES (?, ?, ?, 'device_unbound', ?, ?)
    `).run(uuidv4(), licenseId, device.hwid, `Unbound device ${device.device_name}`, req.ip);

    res.json({ message: `Device ${device.device_name} unlinked successfully. New PC slot available.` });
  } catch (error) {
    console.error('Error unbinding device:', error);
    res.status(500).json({ error: error.message || 'Failed to unbind device' });
  }
};

/**
 * Seller / Admin: Extend or Upgrade an existing subscription
 */
exports.extendLicense = async (req, res) => {
  try {
    const db = getDb();
    const { licenseId, addDays, tier, makeLifetime, newMaxDevices } = req.body;

    const license = db.prepare('SELECT * FROM licenses WHERE id = ?').get(licenseId);
    if (!license) {
      return res.status(404).json({ error: 'License not found' });
    }

    let newExpiresAt = license.expires_at;
    let newTier = tier || license.tier;
    let maxDevices = newMaxDevices !== undefined ? parseInt(newMaxDevices, 10) : license.max_devices;

    if (makeLifetime || newTier === 'lifetime') {
      newExpiresAt = null;
      newTier = 'lifetime';
    } else if (addDays && addDays > 0) {
      const currentExp = license.expires_at ? new Date(license.expires_at) : new Date();
      const baseDate = currentExp > new Date() ? currentExp : new Date();
      newExpiresAt = new Date(baseDate.getTime() + addDays * 24 * 60 * 60 * 1000).toISOString();
    }

    db.prepare(`
      UPDATE licenses 
      SET expires_at = ?, tier = ?, max_devices = ?, status = 'active', updated_at = datetime('now')
      WHERE id = ?
    `).run(newExpiresAt, newTier, maxDevices, licenseId);

    db.prepare(`
      INSERT INTO license_logs (id, license_id, event_type, details, ip_address)
      VALUES (?, ?, 'extended', ?, ?)
    `).run(uuidv4(), licenseId, `Extended/Upgraded to ${newTier}`, req.ip);

    res.json({ message: 'License updated successfully' });
  } catch (error) {
    console.error('Error extending license:', error);
    res.status(500).json({ error: error.message || 'Failed to extend license' });
  }
};

/**
 * Seller / Admin: Delete a license permanently
 */
exports.deleteLicense = async (req, res) => {
  try {
    const db = getDb();
    const { id } = req.params;
    db.prepare('DELETE FROM licenses WHERE id = ?').run(id);
    res.json({ message: 'License deleted successfully' });
  } catch (error) {
    console.error('Error deleting license:', error);
    res.status(500).json({ error: error.message || 'Failed to delete license' });
  }
};

function resolveLicensePermissions(license, db) {
  let modules = [];
  if (license.custom_modules) {
    try {
      modules = JSON.parse(license.custom_modules);
    } catch (_) {}
  }
  // If not explicitly customized, load live features from subscription_plans table
  if (!modules || modules.length === 0) {
    const plan = db.prepare('SELECT * FROM subscription_plans WHERE plan_code = ? OR id = ?').get(license.tier, license.tier);
    if (plan && plan.features_json) {
      try {
        modules = JSON.parse(plan.features_json);
      } catch (_) {}
    }
  }
  return Array.isArray(modules) ? modules : [];
}

/**
 * Client PC Endpoint: Online Activation & HWID Device Binding
 */
exports.clientActivate = async (req, res) => {
  try {
    const db = getDb();
    const { license_key, hwid, device_name = 'Windows PC', os_info = 'Windows' } = req.body;

    if (!license_key || !hwid) {
      return res.status(400).json({ error: 'License key and Device HWID are required' });
    }

    const cleanKey = license_key.trim();
    const license = db.prepare('SELECT * FROM licenses WHERE license_key = ?').get(cleanKey);

    if (!license) {
      return res.status(404).json({ error: 'License key not found in central registry' });
    }

    if (license.status === 'revoked' || license.status === 'suspended') {
      return res.status(403).json({
        error: 'This license has been suspended or revoked by the administrator. Contact support.',
      });
    }

    const now = new Date();
    if (license.expires_at && new Date(license.expires_at) < now && license.tier !== 'lifetime') {
      return res.status(403).json({
        error: `This license expired on ${license.expires_at.split('T')[0]}. Please renew your subscription.`,
      });
    }

    // Check if this HWID is already registered on this license
    const existingDevice = db.prepare('SELECT * FROM license_devices WHERE license_id = ? AND hwid = ?').get(license.id, hwid);

    if (existingDevice) {
      if (existingDevice.is_blocked) {
        return res.status(403).json({ error: 'This specific device has been blocked by the administrator.' });
      }
      // Update heartbeat and device name
      db.prepare(`
        UPDATE license_devices 
        SET last_heartbeat_at = datetime('now'), ip_address = ?, device_name = ?
        WHERE id = ?
      `).run(req.ip, device_name, existingDevice.id);
    } else {
      // New Device trying to activate: Check device quota
      const deviceCountRes = db.prepare('SELECT COUNT(*) as count FROM license_devices WHERE license_id = ?').get(license.id);
      const currentCount = deviceCountRes ? deviceCountRes.count : 0;
      const maxAllowed = license.max_devices || 1;

      if (currentCount >= maxAllowed) {
        // Log rejection
        db.prepare(`
          INSERT INTO license_logs (id, license_id, hwid, event_type, details, ip_address)
          VALUES (?, ?, ?, 'limit_exceeded', ?, ?)
        `).run(uuidv4(), license.id, hwid, `Attempted activation on ${device_name} (Limit: ${currentCount}/${maxAllowed})`, req.ip);

        return res.status(403).json({
          error: `Device limit reached (${currentCount}/${maxAllowed} PCs registered). Contact seller to add an additional PC or unlink old PC.`,
        });
      }

      // Register new device
      db.prepare(`
        INSERT INTO license_devices (id, license_id, hwid, device_name, os_info, ip_address)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(uuidv4(), license.id, hwid, device_name, os_info, req.ip);

      db.prepare(`
        INSERT INTO license_logs (id, license_id, hwid, event_type, details, ip_address)
        VALUES (?, ?, ?, 'activation', ?, ?)
      `).run(uuidv4(), license.id, hwid, `Activated on new device: ${device_name}`, req.ip);
    }

    const resolvedModules = resolveLicensePermissions(license, db);

    res.json({
      success: true,
      message: `License successfully activated for ${license.institution_name} (${license.tier.toUpperCase()})`,
      license: {
        institution_name: license.institution_name,
        customer_name: license.customer_name,
        tier: license.tier,
        issued_at: license.issued_at,
        expires_at: license.expires_at,
        max_devices: license.max_devices,
        max_students: license.max_students,
        allowed_modules: resolvedModules,
        raw_key: license.license_key,
        status: license.status,
      },
    });
  } catch (error) {
    console.error('Error during client activation:', error);
    res.status(500).json({ error: error.message || 'Activation failed' });
  }
};

/**
 * Client PC Endpoint: Live Heartbeat & Dynamic Permissions Sync
 */
exports.clientHeartbeat = async (req, res) => {
  try {
    const db = getDb();
    const { license_key, hwid } = req.body;

    if (!license_key || !hwid) {
      return res.status(400).json({ error: 'Key and HWID required' });
    }

    const license = db.prepare('SELECT * FROM licenses WHERE license_key = ?').get(license_key);
    if (!license) {
      return res.status(404).json({ error: 'License key not found', is_valid: false });
    }

    if (license.status === 'revoked' || license.status === 'suspended') {
      return res.status(403).json({ error: 'License revoked', is_valid: false });
    }

    let device = db.prepare('SELECT * FROM license_devices WHERE license_id = ? AND hwid = ?').get(license.id, hwid);
    if (!device) {
      const deviceCountRes = db.prepare('SELECT COUNT(*) as count FROM license_devices WHERE license_id = ?').get(license.id);
      const currentCount = deviceCountRes ? deviceCountRes.count : 0;
      const maxAllowed = license.max_devices || 1;
      if (currentCount < maxAllowed) {
        db.prepare(`
          INSERT INTO license_devices (id, license_id, hwid, device_name, os_info, ip_address)
          VALUES (?, ?, ?, 'Windows PC', 'Windows', ?)
        `).run(uuidv4(), license.id, hwid, req.ip);
        device = db.prepare('SELECT * FROM license_devices WHERE license_id = ? AND hwid = ?').get(license.id, hwid);
      }
    }

    if (device && device.is_blocked) {
      return res.status(403).json({ error: 'Device has been blocked by administrator', is_valid: false });
    }

    if (device) {
      db.prepare('UPDATE license_devices SET last_heartbeat_at = datetime(\'now\'), ip_address = ? WHERE id = ?').run(req.ip, device.id);
    }

    const isExpired = license.expires_at && new Date(license.expires_at) < new Date() && license.tier !== 'lifetime';
    const resolvedModules = resolveLicensePermissions(license, db);

    res.json({
      is_valid: !isExpired,
      status: license.status,
      tier: license.tier,
      expires_at: license.expires_at,
      allowed_modules: resolvedModules,
      institution_name: license.institution_name,
      max_devices: license.max_devices,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Client PC Endpoint: Deactivate & Unbind Hardware
 */
exports.clientDeactivate = async (req, res) => {
  try {
    const db = getDb();
    const { license_key, hwid } = req.body;

    if (!license_key || !hwid) {
      return res.status(400).json({ error: 'License key and Device HWID are required' });
    }

    const cleanKey = license_key.trim();
    const license = db.prepare('SELECT * FROM licenses WHERE license_key = ?').get(cleanKey);

    if (license) {
      // Remove device hardware binding
      db.prepare('DELETE FROM license_devices WHERE license_id = ? AND hwid = ?').run(license.id, hwid);

      // Log event
      db.prepare(`
        INSERT INTO license_logs (id, license_id, event_type, details, ip_address)
        VALUES (?, ?, 'deactivated', ?, ?)
      `).run(uuidv4(), license.id, `Deactivated by client on HWID: ${hwid}`, req.ip);
    }

    res.json({ message: 'License deactivated and PC unbound successfully' });
  } catch (error) {
    console.error('Error during client deactivation:', error);
    res.status(500).json({ error: error.message || 'Deactivation failed' });
  }
};

/**
 * Get current Seller Owner PIN
 */
exports.getOwnerPin = async (req, res) => {
  try {
    const db = getDb();
    const row = db.prepare("SELECT value FROM settings WHERE key = 'seller_owner_pin'").get();
    res.json({ pin: (row && row.value) ? row.value : '78692' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Change Seller Owner PIN
 */
exports.changeOwnerPin = async (req, res) => {
  try {
    const db = getDb();
    const { oldPin, newPin } = req.body;

    if (!newPin || newPin.trim().length < 4) {
      return res.status(400).json({ error: 'New PIN must be at least 4 digits' });
    }

    const row = db.prepare("SELECT value FROM settings WHERE key = 'seller_owner_pin'").get();
    const currentPin = (row && row.value) ? row.value : '78692';

    // Verify old PIN (allow master fallback 78692 or 123456)
    if (oldPin !== currentPin && oldPin !== '78692' && oldPin !== '123456') {
      return res.status(401).json({ error: 'Current PIN is incorrect' });
    }

    db.prepare(`
      INSERT INTO settings (key, value, updated_at) 
      VALUES ('seller_owner_pin', ?, datetime('now'))
      ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')
    `).run(newPin.trim());

    res.json({ message: 'Owner PIN updated successfully', newPin: newPin.trim() });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Get Feature Catalog (50+ Granular Micro-Features)
 */
exports.getFeatureCatalog = (req, res) => {
  res.json({ catalog: FEATURE_CATALOG });
};

/**
 * Get All Subscription Plan Templates (Active plans for Customer App & Seller App)
 */
exports.getAllPlans = async (req, res) => {
  try {
    const db = getDb();
    const rows = db.prepare('SELECT * FROM subscription_plans WHERE is_active = 1 ORDER BY sort_order ASC').all();
    const plans = rows.map(p => {
      let features = [];
      try {
        features = JSON.parse(p.features_json || '[]');
      } catch (_) {}
      return {
        ...p,
        features,
      };
    });
    res.json({ plans });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Admin: Create New Subscription Plan Template
 */
exports.createPlan = async (req, res) => {
  try {
    const db = getDb();
    const {
      name,
      plan_code,
      description = '',
      price = 0,
      validity_days = 365,
      max_devices = 1,
      is_lifetime = 0,
      features = [],
    } = req.body;

    if (!name || !plan_code) {
      return res.status(400).json({ error: 'Plan Name and Plan Code are required' });
    }

    const planId = 'plan_' + uuidv4().substring(0, 8);
    const featuresJson = JSON.stringify(Array.isArray(features) ? features : []);

    const maxSort = db.prepare('SELECT MAX(sort_order) as max_sort FROM subscription_plans').get();
    const nextSort = (maxSort && maxSort.max_sort) ? maxSort.max_sort + 1 : 1;

    db.prepare(`
      INSERT INTO subscription_plans (
        id, plan_code, name, description, price, validity_days, max_devices, is_lifetime, is_active, sort_order, features_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
    `).run(
      planId,
      plan_code.toLowerCase().trim().replace(/\s+/g, '_'),
      name.trim(),
      description.trim(),
      parseFloat(price) || 0,
      parseInt(validity_days, 10) || 365,
      parseInt(max_devices, 10) || 1,
      is_lifetime ? 1 : 0,
      nextSort,
      featuresJson
    );

    const created = db.prepare('SELECT * FROM subscription_plans WHERE id = ?').get(planId);
    res.status(201).json({ message: 'Plan created successfully', plan: { ...created, features } });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Admin: Update Existing Subscription Plan Template
 */
exports.updatePlan = async (req, res) => {
  try {
    const db = getDb();
    const { id } = req.params;
    const {
      name,
      description,
      price,
      validity_days,
      max_devices,
      is_lifetime,
      features,
    } = req.body;

    const existing = db.prepare('SELECT * FROM subscription_plans WHERE id = ?').get(id);
    if (!existing) {
      return res.status(404).json({ error: 'Plan not found' });
    }

    const updatedFeaturesJson = features !== undefined
      ? JSON.stringify(Array.isArray(features) ? features : [])
      : existing.features_json;

    db.prepare(`
      UPDATE subscription_plans SET
        name = ?,
        description = ?,
        price = ?,
        validity_days = ?,
        max_devices = ?,
        is_lifetime = ?,
        features_json = ?,
        updated_at = datetime('now')
      WHERE id = ?
    `).run(
      name !== undefined ? name.trim() : existing.name,
      description !== undefined ? description.trim() : existing.description,
      price !== undefined ? parseFloat(price) : existing.price,
      validity_days !== undefined ? parseInt(validity_days, 10) : existing.validity_days,
      max_devices !== undefined ? parseInt(max_devices, 10) : existing.max_devices,
      is_lifetime !== undefined ? (is_lifetime ? 1 : 0) : existing.is_lifetime,
      updatedFeaturesJson,
      id
    );

    // Sync all customer licenses using this plan template to pick up the updated feature set
    db.prepare('UPDATE licenses SET custom_modules = NULL WHERE tier = ?').run(existing.plan_code);

    const updated = db.prepare('SELECT * FROM subscription_plans WHERE id = ?').get(id);
    res.json({ message: 'Plan updated successfully', plan: { ...updated, features: JSON.parse(updated.features_json || '[]') } });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Admin: Delete Subscription Plan Template
 */
exports.deletePlan = async (req, res) => {
  try {
    const db = getDb();
    const { id } = req.params;
    db.prepare('DELETE FROM subscription_plans WHERE id = ?').run(id);
    res.json({ message: 'Plan deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Get Free Trial Configuration
 */
exports.getTrialConfig = async (req, res) => {
  try {
    const db = getDb();
    const row = db.prepare("SELECT value FROM settings WHERE key = 'trial_config'").get();
    let config = { duration_days: 14, is_enabled: true, features: [] };
    if (row && row.value) {
      try { config = JSON.parse(row.value); } catch (_) {}
    }
    res.json({ trial_config: config });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Admin: Update Free Trial Configuration
 */
exports.updateTrialConfig = async (req, res) => {
  try {
    const db = getDb();
    const { duration_days = 14, is_enabled = true, features = [] } = req.body;

    const configJson = JSON.stringify({
      duration_days: parseInt(duration_days, 10) || 14,
      is_enabled: !!is_enabled,
      features: Array.isArray(features) ? features : [],
    });

    db.prepare(`
      INSERT INTO settings (key, value, updated_at)
      VALUES ('trial_config', ?, datetime('now'))
      ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = datetime('now')
    `).run(configJson);

    res.json({ message: 'Free Trial configuration updated successfully', trial_config: JSON.parse(configJson) });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Client PC Endpoint: Free Trial Telemetry Ping
 */
exports.clientTrialPing = async (req, res) => {
  try {
    const db = getDb();
    const { hwid, device_name = 'Windows PC', os_info = 'Windows', trial_installed_at, institution_name = 'Trial Madarsa' } = req.body;

    if (!hwid) {
      return res.status(400).json({ error: 'Device HWID is required' });
    }

    db.exec(`
      CREATE TABLE IF NOT EXISTS trial_devices (
        hwid TEXT PRIMARY KEY,
        institution_name TEXT,
        device_name TEXT,
        os_info TEXT,
        ip_address TEXT,
        trial_installed_at TEXT,
        last_heartbeat_at TEXT DEFAULT (datetime('now')),
        is_blocked INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now'))
      );
    `);

    const existing = db.prepare('SELECT * FROM trial_devices WHERE hwid = ?').get(hwid);

    if (existing) {
      if (existing.is_blocked) {
        return res.status(403).json({ error: 'This trial computer has been blocked by administrator.', is_blocked: true });
      }
      db.prepare(`
        UPDATE trial_devices 
        SET last_heartbeat_at = datetime('now'), ip_address = ?, device_name = ?, os_info = ?, institution_name = ?
        WHERE hwid = ?
      `).run(req.ip, device_name, os_info, institution_name, hwid);
    } else {
      db.prepare(`
        INSERT INTO trial_devices (hwid, institution_name, device_name, os_info, ip_address, trial_installed_at)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(hwid, institution_name, device_name, os_info, req.ip, trial_installed_at || new Date().toISOString());
    }

    // Return current trial config
    const row = db.prepare("SELECT value FROM settings WHERE key = 'trial_config'").get();
    let config = { duration_days: 14, is_enabled: true, features: [] };
    if (row && row.value) {
      try { config = JSON.parse(row.value); } catch (_) {}
    }

    res.json({
      success: true,
      is_blocked: false,
      trial_config: config,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Admin: Get all live free trial devices
 */
exports.getAllTrialUsers = async (req, res) => {
  try {
    const db = getDb();
    db.exec(`
      CREATE TABLE IF NOT EXISTS trial_devices (
        hwid TEXT PRIMARY KEY,
        institution_name TEXT,
        device_name TEXT,
        os_info TEXT,
        ip_address TEXT,
        trial_installed_at TEXT,
        last_heartbeat_at TEXT DEFAULT (datetime('now')),
        is_blocked INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now'))
      );
    `);

    const rows = db.prepare('SELECT * FROM trial_devices ORDER BY last_heartbeat_at DESC').all();
    res.json({ trial_users: rows });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Admin: Block or Unblock a Free Trial Computer (Kill-Switch)
 */
exports.toggleTrialBlock = async (req, res) => {
  try {
    const db = getDb();
    const { hwid, is_blocked } = req.body;

    if (!hwid) {
      return res.status(400).json({ error: 'HWID is required' });
    }

    db.prepare('UPDATE trial_devices SET is_blocked = ? WHERE hwid = ?').run(is_blocked ? 1 : 0, hwid);

    try {
      await FirebaseService.setDocument('trial_devices', hwid, {
        is_blocked: is_blocked === true,
        updated_at: new Date().toISOString(),
      });
    } catch (fbErr) {
      console.error('Firebase error in toggleTrialBlock:', fbErr.message);
    }

    res.json({ message: `Trial computer ${is_blocked ? 'blocked' : 'unblocked'} successfully` });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

/**
 * Admin: Delete a Free Trial Device record
 */
exports.deleteTrialUser = async (req, res) => {
  try {
    const db = getDb();
    const { hwid } = req.params;
    db.prepare('DELETE FROM trial_devices WHERE hwid = ?').run(hwid);
    res.json({ message: 'Trial device record deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
};

