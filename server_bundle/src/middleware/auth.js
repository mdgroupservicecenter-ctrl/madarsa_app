const jwt = require('jsonwebtoken');
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

function authenticateToken(req, res, next) {
  const authHeader = req.headers.authorization;
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'Access token required' });
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET);

    const user = db.prepare(`
      SELECT u.id, u.username, u.full_name, u.email, u.phone, u.avatar, u.is_active
      FROM users u
      WHERE u.id = ? AND u.is_active = 1
    `).get(decoded.userId);

    if (!user) {
      return res.status(401).json({ error: 'User not found or inactive' });
    }

    const roles = db.prepare(USER_ROLES_QUERY).all(user.id);
    const permissions = db.prepare(USER_PERMISSIONS_QUERY).all(user.id);

    req.user = {
      ...user,
      fullName: user.full_name,
      isActive: user.is_active === 1,
      roles,
      permissions,
    };

    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

function requirePermission(module, action) {
  return (req, res, next) => {
    const isAdmin = req.user.roles.some((role) => role.name === 'Admin');
    const hasPermission = req.user.permissions.some(
      (permission) => permission.module === module && permission.action === action,
    );

    if (!isAdmin && !hasPermission) {
      return res.status(403).json({
        error: `Permission denied: ${action} ${module}`,
      });
    }

    next();
  };
}

module.exports = { authenticateToken, requirePermission };
