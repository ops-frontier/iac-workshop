require('dotenv').config();
const express = require('express');
const session = require('express-session');
const passport = require('passport');
const GitHubStrategy = require('passport-github2').Strategy;
const helmet = require('helmet');
const cors = require('cors');
const rateLimit = require('express-rate-limit');
const path = require('path');
const crypto = require('crypto');

const db = require('./database');
const workspaceManager = require('./workspace-manager');

const app = express();
const PORT = process.env.PORT || 3000;
const DOMAIN = process.env.DOMAIN;
const CALLBACK_URL = `https://${DOMAIN}/auth/github/callback`;

// Trust proxy (Nginx reverse proxy)
app.set('trust proxy', 1);

// Security middleware
app.use(helmet({
  contentSecurityPolicy: false // Allow inline scripts for simplicity
}));

app.use(cors({
  origin: `https://${DOMAIN}`,
  credentials: true
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use('/api/', limiter);

// Body parser
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Session configuration
app.use(session({
  secret: process.env.SESSION_SECRET || crypto.randomBytes(32).toString('hex'),
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: true,
    httpOnly: true,
    maxAge: 24 * 60 * 60 * 1000, // 24 hours
    sameSite: 'lax' // Important for OAuth callback
  },
  proxy: true // Trust proxy (Nginx)
}));

// Passport configuration
passport.use(new GitHubStrategy({
  clientID: process.env.GITHUB_CLIENT_ID,
  clientSecret: process.env.GITHUB_CLIENT_SECRET,
  callbackURL: CALLBACK_URL
},
function(accessToken, refreshToken, profile, done) {
  const user = {
    id: profile.id,
    username: profile.username,
    displayName: profile.displayName,
    email: profile.emails && profile.emails[0] ? profile.emails[0].value : null,
    avatar: profile.photos && profile.photos[0] ? profile.photos[0].value : null
  };
  
  // Store or update user in database
  db.upsertUser(user);
  
  return done(null, user);
}
));

passport.serializeUser((user, done) => {
  done(null, user.id);
});

passport.deserializeUser((id, done) => {
  const user = db.getUserById(id);
  done(null, user);
});

app.use(passport.initialize());
app.use(passport.session());

// Static files
app.use(express.static(path.join(__dirname, 'public')));

// Middleware to check authentication
function ensureAuthenticated(req, res, next) {
  if (req.isAuthenticated()) {
    return next();
  }
  res.redirect('/');
}

// Routes

// Home page - redirect to auth if not logged in
app.get('/', (req, res) => {
  if (req.isAuthenticated()) {
    res.redirect('/dashboard');
  } else {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
  }
});

// Auth routes with PKCE support
app.get('/auth/github', (req, res, next) => {
  // Generate state parameter for CSRF protection
  const state = crypto.randomBytes(32).toString('hex');
  req.session.oauthState = state;
  
  console.log('OAuth initiated - State:', state);
  console.log('Session ID:', req.sessionID);
  
  passport.authenticate('github', {
    scope: ['user:email'],
    state: state
  })(req, res, next);
});

app.get('/auth/github/callback',
  (req, res, next) => {
    console.log('OAuth callback - Query state:', req.query.state);
    console.log('Session state:', req.session.oauthState);
    console.log('Session ID:', req.sessionID);
    
    // Verify state parameter
    if (req.query.state !== req.session.oauthState) {
      console.error('State mismatch! Query:', req.query.state, 'Session:', req.session.oauthState);
      return res.status(403).send('Invalid state parameter. Please try logging in again.');
    }
    delete req.session.oauthState;
    next();
  },
  passport.authenticate('github', { failureRedirect: '/' }),
  (req, res) => {
    res.redirect('/dashboard');
  }
);

app.get('/logout', (req, res) => {
  req.logout((err) => {
    if (err) { return next(err); }
    res.redirect('/');
  });
});

// Dashboard
app.get('/dashboard', ensureAuthenticated, (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'dashboard.html'));
});

// API Routes

// Get user's workspaces
app.get('/api/workspaces', ensureAuthenticated, (req, res) => {
  const workspaces = db.getUserWorkspaces(req.user.id);
  res.json(workspaces);
});

// Create new workspace
app.post('/api/workspaces', ensureAuthenticated, async (req, res) => {
  try {
    const { name, repoUrl, envVars } = req.body;
    
    if (!name || !repoUrl) {
      return res.status(400).json({ error: 'Name and repository URL are required' });
    }
    
    // Validate workspace name
    if (!/^[a-zA-Z0-9_-]+$/.test(name)) {
      return res.status(400).json({ error: 'Invalid workspace name. Use only alphanumeric characters, hyphens, and underscores.' });
    }
    
    // Create workspace
    const workspace = await workspaceManager.createWorkspace(
      req.user.username,
      name,
      repoUrl,
      envVars || {}
    );
    
    // Save to database
    db.createWorkspace({
      userId: req.user.id,
      name: name,
      repoUrl: repoUrl,
      containerId: workspace.containerId,
      status: 'running'
    });
    
    res.json(workspace);
  } catch (error) {
    console.error('Error creating workspace:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get workspace details
app.get('/api/workspaces/:id', ensureAuthenticated, (req, res) => {
  const workspace = db.getWorkspace(req.params.id);
  
  if (!workspace || workspace.user_id !== req.user.id) {
    return res.status(404).json({ error: 'Workspace not found' });
  }
  
  res.json(workspace);
});

// Delete workspace
app.delete('/api/workspaces/:id', ensureAuthenticated, async (req, res) => {
  try {
    const workspace = db.getWorkspace(req.params.id);
    
    if (!workspace || workspace.user_id !== req.user.id) {
      return res.status(404).json({ error: 'Workspace not found' });
    }
    
    // Stop and remove container
    await workspaceManager.deleteWorkspace(workspace.container_id);
    
    // Remove from database
    db.deleteWorkspace(req.params.id);
    
    res.json({ success: true });
  } catch (error) {
    console.error('Error deleting workspace:', error);
    res.status(500).json({ error: error.message });
  }
});

// Start workspace
app.post('/api/workspaces/:id/start', ensureAuthenticated, async (req, res) => {
  try {
    const workspace = db.getWorkspace(req.params.id);
    
    if (!workspace || workspace.user_id !== req.user.id) {
      return res.status(404).json({ error: 'Workspace not found' });
    }
    
    await workspaceManager.startWorkspace(workspace.container_id);
    db.updateWorkspaceStatus(req.params.id, 'running');
    
    res.json({ success: true });
  } catch (error) {
    console.error('Error starting workspace:', error);
    res.status(500).json({ error: error.message });
  }
});

// Stop workspace
app.post('/api/workspaces/:id/stop', ensureAuthenticated, async (req, res) => {
  try {
    const workspace = db.getWorkspace(req.params.id);
    
    if (!workspace || workspace.user_id !== req.user.id) {
      return res.status(404).json({ error: 'Workspace not found' });
    }
    
    await workspaceManager.stopWorkspace(workspace.container_id);
    db.updateWorkspaceStatus(req.params.id, 'stopped');
    
    res.json({ success: true });
  } catch (error) {
    console.error('Error stopping workspace:', error);
    res.status(500).json({ error: error.message });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Initialize database
db.initialize();

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Pseudo CodeSpaces server running on port ${PORT}`);
  console.log(`Domain: ${DOMAIN}`);
});
