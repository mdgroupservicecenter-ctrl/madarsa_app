const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const { db } = require('../config/database');

function normalizeIds(values) {
  if (!Array.isArray(values)) {
    return [];
  }

  return [...new Set(values.map((value) => String(value).trim()).filter(Boolean))];
}

function validateRoleIds(roleIds) {
  if (roleIds.length === 0) {
    return true;
  }

  const placeholders = roleIds.map(() => '?').join(', ');
  const rows = db.prepare(`
    SELECT id FROM roles WHERE id IN (${placeholders}) AND is_active = 1
  `).all(...roleIds);

  return rows.length === roleIds.length;
}

function fetchUserRoles(userId) {
  return db.prepare(`
    SELECT r.id, r.name, r.is_system, r.is_active
    FROM roles r
    JOIN user_roles ur ON r.id = ur.role_id
    WHERE ur.user_id = ?
    ORDER BY r.name
  `).all(userId);
}

const userController = {
  getAll(req, res) {
    try {
      const users = db.prepare(`
        SELECT u.id, u.username, u.full_name, u.email, u.phone, u.avatar,
               u.is_active, u.created_at, u.updated_at
        FROM users u
        ORDER BY u.created_at DESC
      `).all().map((user) => ({
        ...user,
        roles: fetchUserRoles(user.id),
      }));

      res.json({ users });
    } catch (error) {
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  getById(req, res) {
    try {
      const user = db.prepare(`
        SELECT u.id, u.username, u.full_name, u.email, u.phone, u.avatar,
               u.is_active, u.created_at, u.updated_at
        FROM users u
        WHERE u.id = ?
      `).get(req.params.id);

      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }

      const roles = fetchUserRoles(user.id);
      const permissions = db.prepare(`
        SELECT DISTINCT p.id, p.module, p.action, p.description
        FROM permissions p
        JOIN role_permissions rp ON p.id = rp.permission_id
        JOIN roles r ON r.id = rp.role_id
        JOIN user_roles ur ON rp.role_id = ur.role_id
        WHERE ur.user_id = ? AND r.is_active = 1
        ORDER BY p.module, p.action
      `).all(user.id);

      res.json({ user: { ...user, roles, permissions } });
    } catch (error) {
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  create(req, res) {
    try {
      const username = req.body.username?.trim();
      const password = req.body.password;
      const fullName = req.body.fullName?.trim();
      const email = req.body.email?.trim() || null;
      const phone = req.body.phone?.trim() || null;
      const roleIds = normalizeIds(req.body.roleIds);

      if (!username || !password || !fullName) {
        return res.status(400).json({ error: 'Username, password, and full name are required' });
      }

      if (password.length < 6) {
        return res.status(400).json({ error: 'Password must be at least 6 characters' });
      }

      const existing = db.prepare('SELECT id FROM users WHERE lower(username) = lower(?)').get(username);
      if (existing) {
        return res.status(409).json({ error: 'Username already exists' });
      }

      if (!validateRoleIds(roleIds)) {
        return res.status(400).json({ error: 'One or more role IDs are invalid or inactive' });
      }

      const userId = uuidv4();
      const hashedPassword = bcrypt.hashSync(password, 10);
      const insertUserRole = db.prepare(`
        INSERT INTO user_roles (user_id, role_id)
        VALUES (?, ?)
      `);

      const transaction = db.transaction(() => {
        db.prepare(`
          INSERT INTO users (id, username, password, full_name, email, phone)
          VALUES (?, ?, ?, ?, ?, ?)
        `).run(userId, username, hashedPassword, fullName, email, phone);

        for (const roleId of roleIds) {
          insertUserRole.run(userId, roleId);
        }
      });

      transaction();

      db.prepare(`
        INSERT INTO activity_logs (id, user_id, action, module, details, ip_address)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(
        uuidv4(),
        req.user.id,
        'create',
        'users',
        `Created user: ${username}`,
        req.ip,
      );

      const user = db.prepare(`
        SELECT id, username, full_name, email, phone, is_active, created_at, updated_at
        FROM users
        WHERE id = ?
      `).get(userId);

      res.status(201).json({ user: { ...user, roles: fetchUserRoles(userId) } });
    } catch (error) {
      console.error('Create user error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  update(req, res) {
    try {
      const userId = req.params.id;
      const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);

      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }

      const fullName = req.body.fullName?.trim() || user.full_name;
      const email = req.body.email !== undefined ? (req.body.email?.trim() || null) : user.email;
      const phone = req.body.phone !== undefined ? (req.body.phone?.trim() || null) : user.phone;
      const isActive = req.body.isActive !== undefined ? (req.body.isActive ? 1 : 0) : user.is_active;
      const roleIds = req.body.roleIds === undefined ? null : normalizeIds(req.body.roleIds);

      if (roleIds && !validateRoleIds(roleIds)) {
        return res.status(400).json({ error: 'One or more role IDs are invalid or inactive' });
      }

      const insertUserRole = db.prepare(`
        INSERT INTO user_roles (user_id, role_id)
        VALUES (?, ?)
      `);

      const transaction = db.transaction(() => {
        db.prepare(`
          UPDATE users
          SET full_name = ?, email = ?, phone = ?, is_active = ?, updated_at = datetime('now')
          WHERE id = ?
        `).run(fullName, email, phone, isActive, userId);

        if (roleIds) {
          db.prepare('DELETE FROM user_roles WHERE user_id = ?').run(userId);
          for (const roleId of roleIds) {
            insertUserRole.run(userId, roleId);
          }
        }
      });

      transaction();

      db.prepare(`
        INSERT INTO activity_logs (id, user_id, action, module, details, ip_address)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(
        uuidv4(),
        req.user.id,
        'update',
        'users',
        `Updated user: ${user.username}`,
        req.ip,
      );

      res.json({ message: 'User updated successfully' });
    } catch (error) {
      console.error('Update user error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  resetPassword(req, res) {
    try {
      const { newPassword } = req.body;
      const userId = req.params.id;

      if (!newPassword || newPassword.length < 6) {
        return res.status(400).json({ error: 'Password must be at least 6 characters' });
      }

      const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }

      const hashedPassword = bcrypt.hashSync(newPassword, 10);
      db.prepare(`
        UPDATE users
        SET password = ?, updated_at = datetime('now')
        WHERE id = ?
      `).run(hashedPassword, userId);

      db.prepare(`
        INSERT INTO activity_logs (id, user_id, action, module, details, ip_address)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(
        uuidv4(),
        req.user.id,
        'reset_password',
        'users',
        `Reset password for: ${user.username}`,
        req.ip,
      );

      res.json({ message: 'Password reset successfully' });
    } catch (error) {
      res.status(500).json({ error: 'Internal server error' });
    }
  },
};

module.exports = userController;
