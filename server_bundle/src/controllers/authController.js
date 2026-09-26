const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { db } = require('../config/database');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../../.env') });

const JWT_SECRET = process.env.JWT_SECRET || 'madarsa_super_secret_key_2026_change_in_production';

const USER_ROLES_QUERY = `
  SELECT r.id, r.name, r.description, r.is_system, r.is_active
  FROM roles r
  JOIN user_roles ur ON r.id = ur.role_id
  WHERE ur.user_id = ? AND r.is_active = 1
`;

const USER_PERMISSIONS_QUERY = `
  SELECT DISTINCT p.id, p.module, p.action, p.description
  FROM permissions p
  JOIN role_permissions rp ON p.id = rp.permission_id
  JOIN roles r ON r.id = rp.role_id
  JOIN user_roles ur ON ur.role_id = r.id
  WHERE ur.user_id = ? AND r.is_active = 1
  ORDER BY p.module, p.action
`;

const authController = {
  login(req, res) {
    try {
      const { username, password } = req.body;

      if (!username || !password) {
        return res.status(400).json({ error: 'Username and password are required' });
      }

      const user = db.prepare(`
        SELECT * FROM users WHERE username = ? AND is_active = 1
      `).get(username.trim());

      if (!user || !bcrypt.compareSync(password, user.password)) {
        return res.status(401).json({ error: 'Invalid username or password' });
      }

      const roles = db.prepare(USER_ROLES_QUERY).all(user.id);
      const permissions = db.prepare(USER_PERMISSIONS_QUERY).all(user.id);

      const token = jwt.sign(
        { userId: user.id },
        JWT_SECRET,
        { expiresIn: process.env.JWT_EXPIRES_IN || '7d' },
      );

      try {
        db.prepare(`
          INSERT INTO activity_logs (id, user_id, action, module, details, ip_address)
          VALUES (?, ?, ?, ?, ?, ?)
        `).run(
          uuidv4(),
          user.id,
          'login',
          'auth',
          'User logged in',
          req.ip,
        );
      } catch (logErr) {
        console.warn('[AuthController] Activity log recording failed (non-fatal):', logErr.message);
      }

      res.json({
        token,
        user: {
          id: user.id,
          username: user.username,
          fullName: user.full_name,
          email: user.email,
          phone: user.phone,
          avatar: user.avatar,
          isActive: user.is_active === 1,
          roles,
          permissions,
        },
      });
    } catch (error) {
      console.error('Login error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  getProfile(req, res) {
    try {
      res.json({ user: req.user });
    } catch (error) {
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  changePassword(req, res) {
    try {
      const { currentPassword, newPassword } = req.body;

      if (!currentPassword || !newPassword) {
        return res.status(400).json({ error: 'Current and new password are required' });
      }

      if (newPassword.length < 6) {
        return res.status(400).json({ error: 'New password must be at least 6 characters' });
      }

      const user = db.prepare('SELECT * FROM users WHERE id = ?').get(req.user.id);

      if (!user || !bcrypt.compareSync(currentPassword, user.password)) {
        return res.status(401).json({ error: 'Current password is incorrect' });
      }

      const hashedPassword = bcrypt.hashSync(newPassword, 10);
      db.prepare(`
        UPDATE users
        SET password = ?, updated_at = datetime('now')
        WHERE id = ?
      `).run(hashedPassword, req.user.id);

      db.prepare(`
        INSERT INTO activity_logs (id, user_id, action, module, details, ip_address)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(
        uuidv4(),
        req.user.id,
        'change_password',
        'auth',
        'Password changed',
        req.ip,
      );

      res.json({ message: 'Password changed successfully' });
    } catch (error) {
      res.status(500).json({ error: 'Internal server error' });
    }
  },
};

module.exports = authController;
