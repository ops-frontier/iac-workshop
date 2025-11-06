const pino = require('pino');

// Get log level from environment variable or default to 'info'
const logLevel = process.env.LOG_LEVEL || 'info';

// Create base logger
const logger = pino({
  level: logLevel,
  formatters: {
    level: (label) => {
      return { level: label };
    },
  },
  timestamp: pino.stdTimeFunctions.isoTime,
  base: {
    service: 'pseudo-codespaces',
    pid: process.pid,
  },
});

/**
 * Create a child logger with additional context
 * @param {Object} context - Additional context to add to logs
 * @returns {Object} Child logger with merged context
 */
function createContextLogger(context) {
  return logger.child(context);
}

/**
 * Create a user-scoped logger
 * @param {string} username - Username
 * @returns {Object} Logger with user context
 */
function createUserLogger(username) {
  return createContextLogger({ user: username });
}

/**
 * Create a workspace-scoped logger
 * @param {string} username - Username
 * @param {string} workspaceName - Workspace name
 * @returns {Object} Logger with user and workspace context
 */
function createWorkspaceLogger(username, workspaceName) {
  return createContextLogger({ 
    user: username, 
    workspace: workspaceName 
  });
}

/**
 * Create an action-scoped logger
 * @param {string} username - Username
 * @param {string} workspaceName - Workspace name
 * @param {string} action - Action being performed
 * @returns {Object} Logger with user, workspace, and action context
 */
function createActionLogger(username, workspaceName, action) {
  return createContextLogger({ 
    user: username, 
    workspace: workspaceName,
    action: action
  });
}

/**
 * Create a container-scoped logger
 * @param {string} username - Username
 * @param {string} workspaceName - Workspace name
 * @param {string} containerId - Container ID
 * @returns {Object} Logger with user, workspace, and container context
 */
function createContainerLogger(username, workspaceName, containerId) {
  return createContextLogger({ 
    user: username, 
    workspace: workspaceName,
    containerId: containerId
  });
}

module.exports = {
  logger,
  createContextLogger,
  createUserLogger,
  createWorkspaceLogger,
  createActionLogger,
  createContainerLogger,
};
