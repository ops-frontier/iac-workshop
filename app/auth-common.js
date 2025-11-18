const passport = require('passport');
const GitHubStrategy = require('passport-github2').Strategy;
const crypto = require('crypto');

/**
 * Configure GitHub OAuth strategy for an Express app
 * @param {Object} options - Configuration options
 * @param {Object} options.passport - Passport instance
 * @param {string} options.clientID - GitHub OAuth client ID
 * @param {string} options.clientSecret - GitHub OAuth client secret
 * @param {string} options.callbackURL - OAuth callback URL
 * @param {string} options.targetOrganization - Target GitHub organization (optional)
 * @param {Function} options.onAuthSuccess - Callback(accessToken, profile) => user object or null/false
 * @param {Object} options.logger - Logger instance
 */
function configureGitHubAuth(options) {
  const { clientID, clientSecret, callbackURL, targetOrganization, onAuthSuccess, logger, passport } = options;
  
  passport.use(new GitHubStrategy({
    clientID: clientID,
    clientSecret: clientSecret,
    callbackURL: callbackURL
  },
  async function(accessToken, refreshToken, profile, done) {
    const logContext = { username: profile.username, profileId: profile.id };
    logger.info(logContext, 'GitHub OAuth callback');
    
    try {
      // Check organization membership if required
      if (targetOrganization) {
        logger.debug({ ...logContext, organization: targetOrganization }, 'Checking organization membership');
        
        const https = require('https');
        const checkMembership = () => {
          return new Promise((resolve, reject) => {
            const options = {
              hostname: 'api.github.com',
              path: `/user/orgs`,
              method: 'GET',
              headers: {
                'Authorization': `token ${accessToken}`,
                'User-Agent': 'Workspaces-App',
                'Accept': 'application/vnd.github.v3+json'
              }
            };
            
            const req = https.request(options, (res) => {
              let data = '';
              res.on('data', (chunk) => { data += chunk; });
              res.on('end', () => {
                if (res.statusCode === 200) {
                  resolve(JSON.parse(data));
                } else {
                  reject(new Error(`GitHub API returned ${res.statusCode}: ${data}`));
                }
              });
            });
            
            req.on('error', reject);
            req.end();
          });
        };
        
        const userOrgs = await checkMembership();
        const isMember = userOrgs.some(org => org.login === targetOrganization);
        
        if (!isMember) {
          logger.warn({ ...logContext, organization: targetOrganization }, 'User is not a member of the required organization');
          return done(null, false, { 
            message: `ユーザー ${profile.username} は組織 ${targetOrganization} に所属していません` 
          });
        }
        
        logger.info({ ...logContext, organization: targetOrganization }, 'Organization membership verified');
      }
      
      // Call application-specific success handler
      const user = await onAuthSuccess(accessToken, profile);
      
      if (!user) {
        logger.warn(logContext, 'Authentication rejected by application handler');
        return done(null, false, { message: '認証に失敗しました' });
      }
      
      return done(null, user);
    } catch (error) {
      logger.error({ ...logContext, error: error.message }, 'Error during OAuth callback');
      return done(error);
    }
  }));
}

/**
 * Create OAuth route handlers
 * @param {Object} options - Configuration options
 * @param {Object} options.passport - Passport instance
 * @param {Object} options.logger - Logger instance
 * @param {string} options.defaultReturnTo - Default redirect URL after successful authentication
 * @param {Object} options.errorMessages - Error message templates
 */
function createOAuthRoutes(options) {
  const { passport, logger, defaultReturnTo, errorMessages = {} } = options;
  const failureRedirect = '/';
  const successRedirect = defaultReturnTo || '/dashboard';
  
  return {
    // Initiate OAuth flow
    initiateAuth: (req, res, next) => {
      // Generate state parameter for CSRF protection
      const state = crypto.randomBytes(32).toString('hex');
      req.session.oauthState = state;
      
      // Store returnTo URL if provided
      if (req.query.returnTo) {
        req.session.returnTo = req.query.returnTo;
        logger.info({ sessionId: req.sessionID, state, returnTo: req.query.returnTo }, 'OAuth initiated with returnTo');
      } else {
        logger.info({ sessionId: req.sessionID, state }, 'OAuth initiated without returnTo');
      }
      
      // Save session before redirecting to GitHub
      req.session.save((err) => {
        if (err) {
          logger.error({ error: err.message }, 'Failed to save session');
          return res.status(500).send('Session error');
        }
        
        logger.debug({ sessionId: req.sessionID, savedReturnTo: req.session.returnTo }, 'Session saved before OAuth redirect');
        
        passport.authenticate('github', {
          scope: ['user:email', 'read:org', 'repo'],
          state: state
        })(req, res, next);
      });
    },
    
    // Handle OAuth callback
    handleCallback: [
      // Verify state parameter
      (req, res, next) => {
        const callbackLogger = logger.child({ 
          sessionId: req.sessionID,
          queryState: req.query.state,
          sessionState: req.session.oauthState,
          hasSession: !!req.session,
          sessionReturnTo: req.session ? req.session.returnTo : undefined
        });
        
        callbackLogger.info('OAuth callback received');
        
        // Check if session exists
        if (!req.session || !req.session.oauthState) {
          callbackLogger.error({ hasSession: !!req.session }, 'Session lost during OAuth callback');
          return res.status(403).send('Session lost during authentication. Please try logging in again.');
        }
        
        // Verify state parameter
        if (req.query.state !== req.session.oauthState) {
          callbackLogger.error('State mismatch in OAuth callback');
          return res.status(403).send('Invalid state parameter. Please try logging in again.');
        }
        delete req.session.oauthState;
        next();
      },
      
      // Authenticate with Passport
      (req, res, next) => {
        passport.authenticate('github', (err, user, info) => {
          const callbackLogger = logger.child({ sessionId: req.sessionID });
          
          if (err) {
            callbackLogger.error({ error: err.message }, 'Authentication error');
            const errMsg = errorMessages.authError || '認証中にエラーが発生しました';
            return res.redirect(`${failureRedirect}?error=` + encodeURIComponent(errMsg));
          }
          
          if (!user) {
            const errorMessage = info && info.message ? info.message : (errorMessages.authFailed || '認証に失敗しました');
            callbackLogger.warn({ info }, 'Authentication failed');
            return res.redirect(`${failureRedirect}?error=` + encodeURIComponent(errorMessage));
          }
          
          // Save returnTo BEFORE req.logIn() because session may be regenerated
          const returnTo = req.session.returnTo || successRedirect || '/';
          const originalSessionId = req.sessionID;
          
          callbackLogger.info({ 
            originalSessionId,
            savedReturnTo: returnTo,
            sessionReturnTo: req.session.returnTo
          }, 'Saving returnTo before login');
          
          // Authentication successful
          req.logIn(user, (err) => {
            if (err) {
              callbackLogger.error({ error: err.message }, 'Login error');
              const errMsg = errorMessages.loginError || 'ログイン処理に失敗しました';
              return res.redirect(`${failureRedirect}?error=` + encodeURIComponent(errMsg));
            }
            
            const newSessionId = req.sessionID;
            callbackLogger.info({ 
              username: user.username,
              originalSessionId,
              newSessionId,
              sessionIdChanged: originalSessionId !== newSessionId,
              redirectTo: returnTo
            }, 'User logged in successfully');
            
            // Save session before redirect
            req.session.save((saveErr) => {
              if (saveErr) {
                callbackLogger.error({ error: saveErr.message }, 'Failed to save session after login');
              }
              
              callbackLogger.info({ username: user.username, redirectTo: returnTo }, 'Redirecting after successful login');
              return res.redirect(returnTo);
            });
          });
        })(req, res, next);
      }
    ]
  };
}

module.exports = {
  configureGitHubAuth,
  createOAuthRoutes
};
