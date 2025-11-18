const express = require('express');
const session = require('express-session');
const passport = require('passport');
const simpleGit = require('simple-git');
const pino = require('pino');
const fs = require('fs').promises;
const path = require('path');

const logger = pino({ level: process.env.LOG_LEVEL || 'info' });
const app = express();

const DOCS_DIR = '/var/docs/docusaurus';
const TARGET_ORG = process.env.TARGET_ORGANIZATION || '';
const DOCS_REPO = 'docusaurus';
const DOCS_BRANCH = 'gh-pages';

// Import shared OAuth configuration
const { configureGitHubAuth, createOAuthRoutes } = require('./auth-common');

// Express configuration
app.use(express.json());

// Serve static files (login page, etc.)
app.use(express.static(path.join(__dirname, 'public')));

app.use(session({
  secret: process.env.SESSION_SECRET || 'docs-renew-secret-key-change-in-production',
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: true,
    httpOnly: true,
    maxAge: 24 * 60 * 60 * 1000, // 24 hours
    sameSite: 'lax'
  },
  proxy: true,
  name: 'docs.sid' // Different session cookie name from workspaces
}));
app.use(passport.initialize());
app.use(passport.session());

// Configure GitHub OAuth strategy
configureGitHubAuth({
  passport,
  clientID: process.env.DOCS_GITHUB_CLIENT_ID,
  clientSecret: process.env.DOCS_GITHUB_CLIENT_SECRET,
  callbackURL: `https://docs.${process.env.DOMAIN}/auth/github/callback`,
  targetOrganization: TARGET_ORG,
  logger,
  onAuthSuccess: (accessToken, profile) => {
    // Create user object from GitHub profile
    const user = {
      id: String(profile.id),
      username: profile.username,
      displayName: profile.displayName,
      email: profile.emails && profile.emails[0] ? profile.emails[0].value : null,
      avatar: profile.photos && profile.photos[0] ? profile.photos[0].value : null,
      githubAccessToken: accessToken
    };
    
    // Return user object for passport session
    return user;
  }
});

passport.serializeUser((user, done) => {
  logger.debug({ userId: user.id }, 'Serializing user');
  done(null, user);
});

passport.deserializeUser((user, done) => {
  logger.debug({ userId: user.id }, 'Deserializing user');
  done(null, user);
});

// Create OAuth routes
const { initiateAuth, handleCallback } = createOAuthRoutes({
  passport,
  logger,
  defaultReturnTo: '/',
  errorMessages: {
    authError: '認証中にエラーが発生しました',
    authFailed: '認証に失敗しました',
    loginError: 'ログイン処理に失敗しました'
  }
});

// Authentication middleware
function ensureAuthenticated(req, res, next) {
  if (req.isAuthenticated()) {
    return next();
  }
  res.status(401).json({ error: 'Authentication required' });
}

// API endpoint for nginx auth_request
app.get('/api/auth/verify', (req, res) => {
  if (req.isAuthenticated()) {
    // Set custom headers for nginx to pass to backend
    res.set('X-Auth-User', req.user.username);
    res.set('X-Auth-User-Id', req.user.id);
    res.status(200).send('OK');
  } else {
    res.status(401).send('Unauthorized');
  }
});

// GitHub OAuth routes
app.get('/auth', initiateAuth);
app.get('/auth/github/callback', handleCallback);

app.get('/auth/failed', (req, res) => {
  res.status(403).json({ error: 'Authentication failed' });
});

// Root endpoint to check authentication status
app.get('/', (req, res) => {
  if (req.isAuthenticated()) {
    res.json({
      authenticated: true,
      user: {
        username: req.user.username,
        displayName: req.user.displayName
      }
    });
  } else {
    res.json({
      authenticated: false,
      message: 'Please authenticate at /auth to access documentation renewal'
    });
  }
});

// Renew endpoint - downloads and deploys documentation
// Requires authentication with GitHub access
app.get('/renew', ensureAuthenticated, async (req, res) => {
  const username = req.user.username;
  const accessToken = req.user.githubAccessToken;
  
  logger.info({ username }, 'Starting documentation renewal');
  
  try {
    // Ensure parent docs directory exists
    await fs.mkdir('/var/docs', { recursive: true });
    
    // Use authenticated user's GitHub access token for private repositories
    const repoUrl = accessToken 
      ? `https://x-access-token:${accessToken}@github.com/${TARGET_ORG}/${DOCS_REPO}.git`
      : `https://github.com/${TARGET_ORG}/${DOCS_REPO}.git`;
    
    // Check if repository already exists
    const gitDir = path.join(DOCS_DIR, '.git');
    let isExistingRepo = false;
    try {
      await fs.access(gitDir);
      isExistingRepo = true;
    } catch (error) {
      // Repository doesn't exist yet
    }
    
    if (isExistingRepo) {
      // Repository exists - pull latest changes
      logger.info({ 
        repo: `${TARGET_ORG}/${DOCS_REPO}`, 
        branch: DOCS_BRANCH,
        hasToken: !!accessToken 
      }, 'Pulling latest changes');
      
      const git = simpleGit(DOCS_DIR);
      
      // Configure remote URL with access token
      await git.remote(['set-url', 'origin', repoUrl]);
      
      // Pull latest changes
      await git.pull('origin', DOCS_BRANCH);
      
      logger.info('Repository updated successfully');
    } else {
      // Repository doesn't exist - clone it
      logger.info({ 
        repo: `${TARGET_ORG}/${DOCS_REPO}`, 
        branch: DOCS_BRANCH,
        hasToken: !!accessToken 
      }, 'Cloning repository');
      
      const git = simpleGit();
      const cloneDir = path.join('/var/docs', DOCS_REPO);
      
      await git.clone(repoUrl, cloneDir, ['--branch', DOCS_BRANCH]);
      
      // Check if clone created the expected directory
      try {
        await fs.access(cloneDir);
        // If cloneDir exists and is different from DOCS_DIR, rename it
        if (cloneDir !== DOCS_DIR) {
          await fs.rename(cloneDir, DOCS_DIR);
          logger.info({ from: cloneDir, to: DOCS_DIR }, 'Renamed cloned directory');
        }
      } catch (error) {
        logger.error({ error: error.message }, 'Failed to verify clone directory');
      }
      
      logger.info('Repository cloned successfully');
    }
    
    logger.info({ username }, 'Documentation renewed successfully');
    
    res.json({
      success: true,
      message: 'Documentation renewed successfully',
      timestamp: new Date().toISOString(),
      user: username
    });
    
  } catch (error) {
    logger.error({ error: error.message, stack: error.stack, username }, 'Error renewing documentation');
    
    res.status(500).json({
      error: 'Failed to renew documentation',
      message: error.message
    });
  }
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Start server
const PORT = process.env.PORT || 3001;
app.listen(PORT, '0.0.0.0', () => {
  logger.info({ port: PORT }, 'Docs renewal service started');
});
