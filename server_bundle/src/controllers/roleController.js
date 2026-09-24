const { v4: uuidv4 } = require('uuid');
const { db } = require('../config/database');

function normalizeIds(values) {
  if (!Array.isArray(values)) {
    return [];
  }

  return [...new Set(values.map((value) => String(value).trim()).filter(Boolean))];
}

function fetchRolePermissions(roleId) {
  return db.prepare(`
    SELECT p.id, p.module, p.action, p.description
    FROM permissions p
    JOIN role_permissions rp ON p.id = rp.permission_id
    WHERE rp.role_id = ?
    ORDER BY p.module, p.action
  `).all(roleId);
}

function validatePermissionIds(permissionIds) {
  if (permissionIds.length === 0) {
    return true;
  }

  const placeholders = permissionIds.map(() => '?').join(', ');
  const rows = db.prepare(`
    SELECT id FROM permissions WHERE id IN (${placeholders})
  `).all(...permissionIds);

  return rows.length === permissionIds.length;
}

const roleController = {
  getAll(req, res) {
    try {
      const roles = db.prepare(`
        SELECT r.*,
          (SELECT COUNT(*) FROM user_roles ur WHERE ur.role_id = r.id) AS user_count
        FROM roles r
        ORDER BY r.created_at DESC
      `).all().map((role) => ({
        ...role,
        permissions: fetchRolePermissions(role.id),
      }));

      res.json({ roles });
    } catch (error) {
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  getById(req, res) {
    try {
      const role = db.prepare('SELECT * FROM roles WHERE id = ?').get(req.params.id);

      if (!role) {
        return res.status(404).json({ error: 'Role not found' });
      }

      res.json({
        role: {
          ...role,
          permissions: fetchRolePermissions(role.id),
        },
      });
    } catch (error) {
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  create(req, res) {
    try {
      const name = req.body.name?.trim();
      const description = req.body.description?.trim() || '';
      const permissionIds = normalizeIds(req.body.permissionIds);

      if (!name) {
        return res.status(400).json({ error: 'Role name is required' });
      }

      const existing = db.prepare('SELECT id FROM roles WHERE lower(name) = lower(?)').get(name);
      if (existing) {
        return res.status(409).json({ error: 'Role name already exists' });
      }

      if (!validatePermissionIds(permissionIds)) {
        return res.status(400).json({ error: 'One or more permission IDs are invalid' });
      }

      const roleId = uuidv4();
      const insertRolePermission = db.prepare(`
        INSERT INTO role_permissions (role_id, permission_id)
        VALUES (?, ?)
      `);

      const transaction = db.transaction(() => {
        db.prepare(`
          INSERT INTO roles (id, name, description)
          VALUES (?, ?, ?)
        `).run(roleId, name, description);

        for (const permissionId of permissionIds) {
          insertRolePermission.run(roleId, permissionId);
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
        'roles',
        `Created role: ${name}`,
        req.ip,
      );

      const role = db.prepare('SELECT * FROM roles WHERE id = ?').get(roleId);
      res.status(201).json({
        role: {
          ...role,
          permissions: fetchRolePermissions(roleId),
        },
      });
    } catch (error) {
      console.error('Create role error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  update(req, res) {
    try {
      const roleId = req.params.id;
      const role = db.prepare('SELECT * FROM roles WHERE id = ?').get(roleId);

      if (!role) {
        return res.status(404).json({ error: 'Role not found' });
      }

      if (role.is_system) {
        return res.status(403).json({ error: 'Cannot modify system roles' });
      }

      const nextName = req.body.name?.trim() || role.name;
      const nextDescription = req.body.description?.trim() ?? role.description;
      const permissionIds = req.body.permissionIds === undefined
        ? null
        : normalizeIds(req.body.permissionIds);

      const nameConflict = db.prepare(`
        SELECT id FROM roles WHERE lower(name) = lower(?) AND id != ?
      `).get(nextName, roleId);
      if (nameConflict) {
        return res.status(409).json({ error: 'Role name already exists' });
      }

      if (permissionIds && !validatePermissionIds(permissionIds)) {
        return res.status(400).json({ error: 'One or more permission IDs are invalid' });
      }

      const insertRolePermission = db.prepare(`
        INSERT INTO role_permissions (role_id, permission_id)
        VALUES (?, ?)
      `);

      const transaction = db.transaction(() => {
        db.prepare(`
          UPDATE roles
          SET name = ?, description = ?, updated_at = datetime('now')
          WHERE id = ?
        `).run(nextName, nextDescription, roleId);

        if (permissionIds) {
          db.prepare('DELETE FROM role_permissions WHERE role_id = ?').run(roleId);

          for (const permissionId of permissionIds) {
            insertRolePermission.run(roleId, permissionId);
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
        'roles',
        `Updated role: ${nextName}`,
        req.ip,
      );

      const updatedRole = db.prepare('SELECT * FROM roles WHERE id = ?').get(roleId);
      res.json({
        role: {
          ...updatedRole,
          permissions: fetchRolePermissions(roleId),
        },
      });
    } catch (error) {
      console.error('Update role error:', error);
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  toggleActive(req, res) {
    try {
      const role = db.prepare('SELECT * FROM roles WHERE id = ?').get(req.params.id);
      if (!role) {
        return res.status(404).json({ error: 'Role not found' });
      }

      if (role.is_system) {
        return res.status(403).json({ error: 'Cannot deactivate system roles' });
      }

      const newStatus = role.is_active ? 0 : 1;
      db.prepare(`
        UPDATE roles
        SET is_active = ?, updated_at = datetime('now')
        WHERE id = ?
      `).run(newStatus, role.id);

      db.prepare(`
        INSERT INTO activity_logs (id, user_id, action, module, details, ip_address)
        VALUES (?, ?, ?, ?, ?, ?)
      `).run(
        uuidv4(),
        req.user.id,
        'toggle_status',
        'roles',
        `${newStatus ? 'Activated' : 'Deactivated'} role: ${role.name}`,
        req.ip,
      );

      res.json({ message: `Role ${newStatus ? 'activated' : 'deactivated'}` });
    } catch (error) {
      res.status(500).json({ error: 'Internal server error' });
    }
  },

  getAllPermissions(req, res) {
    try {
      const permissions = db.prepare(`
        SELECT * FROM permissions ORDER BY module, action
      `).all();

      const grouped = {};
      for (const permission of permissions) {
        if (!grouped[permission.module]) {
          grouped[permission.module] = [];
        }
        grouped[permission.module].push(permission);
      }

      res.json({ permissions, grouped });
    } catch (error) {
      res.status(500).json({ error: 'Internal server error' });
    }
  },
};

module.exports = roleController;
