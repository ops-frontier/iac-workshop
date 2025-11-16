const Database = require('better-sqlite3');
const path = require('path');

const DB_PATH = path.join(__dirname, 'data', 'database.db');
let db;

function initialize() {
  db = new Database(DB_PATH);
  
  // Create tables
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      display_name TEXT,
      email TEXT,
      avatar TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );

    CREATE TABLE IF NOT EXISTS workspaces (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id TEXT,
      name TEXT NOT NULL,
      repo_url TEXT NOT NULL,
      container_id TEXT,
      status TEXT DEFAULT 'stopped',
      devcontainer_build_status TEXT DEFAULT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id),
      UNIQUE(name)
    );

    CREATE INDEX IF NOT EXISTS idx_workspaces_user_id ON workspaces(user_id);
    CREATE INDEX IF NOT EXISTS idx_workspaces_name ON workspaces(name);
  `);
  
  // Migration: Add devcontainer_build_status column if it doesn't exist
  try {
    const columns = db.prepare("PRAGMA table_info(workspaces)").all();
    const hasDevcontainerBuildStatus = columns.some(col => col.name === 'devcontainer_build_status');
    
    if (!hasDevcontainerBuildStatus) {
      db.exec('ALTER TABLE workspaces ADD COLUMN devcontainer_build_status TEXT DEFAULT NULL');
      console.log('Migration: Added devcontainer_build_status column to workspaces table');
    }
  } catch (error) {
    console.error('Migration error:', error);
  }
  
  // Migration: Add github_access_token column to users table if it doesn't exist
  try {
    const userColumns = db.prepare("PRAGMA table_info(users)").all();
    const hasGithubAccessToken = userColumns.some(col => col.name === 'github_access_token');
    
    if (!hasGithubAccessToken) {
      db.exec('ALTER TABLE users ADD COLUMN github_access_token TEXT DEFAULT NULL');
      console.log('Migration: Added github_access_token column to users table');
    }
  } catch (error) {
    console.error('Migration error:', error);
  }
  
  // Migration: Make user_id nullable and change UNIQUE constraint for workspace sharing
  // SQLite doesn't support modifying constraints directly, so we need to recreate the table
  try {
    const columns = db.prepare("PRAGMA table_info(workspaces)").all();
    const userIdColumn = columns.find(col => col.name === 'user_id');
    
    // Check if user_id is still NOT NULL (notnull === 1)
    if (userIdColumn && userIdColumn.notnull === 1) {
      console.log('Migration: Converting workspaces table to support shared workspaces...');
      
      // Create new table with nullable user_id and name-only unique constraint
      db.exec(`
        CREATE TABLE workspaces_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT,
          name TEXT NOT NULL,
          repo_url TEXT NOT NULL,
          container_id TEXT,
          status TEXT DEFAULT 'stopped',
          devcontainer_build_status TEXT DEFAULT NULL,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (user_id) REFERENCES users(id),
          UNIQUE(name)
        );
      `);
      
      // Copy data from old table
      db.exec(`
        INSERT INTO workspaces_new (id, user_id, name, repo_url, container_id, status, devcontainer_build_status, created_at, updated_at)
        SELECT id, user_id, name, repo_url, container_id, status, devcontainer_build_status, created_at, updated_at
        FROM workspaces;
      `);
      
      // Drop old table
      db.exec('DROP TABLE workspaces;');
      
      // Rename new table
      db.exec('ALTER TABLE workspaces_new RENAME TO workspaces;');
      
      // Recreate indexes
      db.exec(`
        CREATE INDEX IF NOT EXISTS idx_workspaces_user_id ON workspaces(user_id);
        CREATE INDEX IF NOT EXISTS idx_workspaces_name ON workspaces(name);
      `);
      
      console.log('Migration: Successfully converted workspaces table to support shared workspaces');
    }
  } catch (error) {
    console.error('Migration error (workspace sharing):', error);
  }
}

function upsertUser(user) {
  const stmt = db.prepare(`
    INSERT INTO users (id, username, display_name, email, avatar, github_access_token, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(id) DO UPDATE SET
      username = excluded.username,
      display_name = excluded.display_name,
      email = excluded.email,
      avatar = excluded.avatar,
      github_access_token = excluded.github_access_token,
      updated_at = CURRENT_TIMESTAMP
  `);
  
  return stmt.run(user.id, user.username, user.displayName, user.email, user.avatar, user.githubAccessToken);
}

function getUserById(id) {
  const stmt = db.prepare('SELECT * FROM users WHERE id = ?');
  return stmt.get(id);
}

function getUserWorkspaces(userId) {
  // Get workspaces owned by user OR available (released) workspaces
  const stmt = db.prepare('SELECT * FROM workspaces WHERE user_id = ? OR user_id IS NULL ORDER BY created_at DESC');
  return stmt.all(userId);
}

function getAllWorkspaces() {
  const stmt = db.prepare('SELECT * FROM workspaces ORDER BY created_at DESC');
  return stmt.all();
}

function createWorkspace(workspace) {
  const stmt = db.prepare(`
    INSERT INTO workspaces (user_id, name, repo_url, container_id, status)
    VALUES (?, ?, ?, ?, ?)
  `);
  
  const result = stmt.run(
    workspace.userId,
    workspace.name,
    workspace.repoUrl,
    workspace.containerId,
    workspace.status
  );
  
  return result.lastInsertRowid;
}

function getWorkspace(id) {
  const stmt = db.prepare('SELECT * FROM workspaces WHERE id = ?');
  return stmt.get(id);
}

function updateWorkspaceStatus(id, status, expectedStatus = null) {
  // If expectedStatus is provided, perform atomic update with status check
  if (expectedStatus !== null) {
    const stmt = db.prepare('UPDATE workspaces SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND status = ?');
    return stmt.run(status, id, expectedStatus);
  }
  // Otherwise, update without check (for backward compatibility or force update)
  const stmt = db.prepare('UPDATE workspaces SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?');
  return stmt.run(status, id);
}

function updateWorkspaceContainer(id, containerId, status, expectedStatus = null) {
  // If expectedStatus is provided, perform atomic update with status check
  if (expectedStatus !== null) {
    const stmt = db.prepare('UPDATE workspaces SET container_id = ?, status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND status = ?');
    return stmt.run(containerId, status, id, expectedStatus);
  }
  // Otherwise, update without check
  const stmt = db.prepare('UPDATE workspaces SET container_id = ?, status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?');
  return stmt.run(containerId, status, id);
}

function getWorkspaceByName(userId, name) {
  const stmt = db.prepare('SELECT * FROM workspaces WHERE user_id = ? AND name = ?');
  return stmt.get(userId, name);
}

function getWorkspaceByNameOnly(name) {
  const stmt = db.prepare('SELECT * FROM workspaces WHERE name = ?');
  return stmt.get(name);
}

function updateWorkspaceOwner(id, userId, expectedStatus) {
  // Atomic update with expected status check
  const stmt = db.prepare('UPDATE workspaces SET user_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND status = ?');
  return stmt.run(userId, id, expectedStatus);
}

function releaseWorkspace(id, expectedUserId, expectedStatus) {
  // Atomic update: release workspace (set user_id to NULL) only if owned by expectedUserId and status matches
  const stmt = db.prepare('UPDATE workspaces SET user_id = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id = ? AND status = ?');
  return stmt.run(id, expectedUserId, expectedStatus);
}

function acquireWorkspace(id, userId, expectedStatus) {
  // Atomic update: acquire workspace (set user_id) only if currently released (user_id IS NULL) and status matches
  const stmt = db.prepare('UPDATE workspaces SET user_id = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND user_id IS NULL AND status = ?');
  return stmt.run(userId, id, expectedStatus);
}

function deleteWorkspace(id) {
  const stmt = db.prepare('DELETE FROM workspaces WHERE id = ?');
  return stmt.run(id);
}

function updateWorkspaceDevcontainerBuildStatus(id, buildStatus) {
  const stmt = db.prepare('UPDATE workspaces SET devcontainer_build_status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?');
  return stmt.run(buildStatus, id);
}

module.exports = {
  initialize,
  upsertUser,
  getUserById,
  getUserWorkspaces,
  getAllWorkspaces,
  createWorkspace,
  getWorkspace,
  getWorkspaceByName,
  getWorkspaceByNameOnly,
  updateWorkspaceStatus,
  updateWorkspaceContainer,
  updateWorkspaceDevcontainerBuildStatus,
  updateWorkspaceOwner,
  releaseWorkspace,
  acquireWorkspace,
  deleteWorkspace
};
