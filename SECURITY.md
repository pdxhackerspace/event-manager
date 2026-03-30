# Security Guide

Security best practices and hardening guide for EventManager in a hackerspace environment (200-500 members, behind Cloudflare).

## Table of Contents
- [Production Security Checklist](#production-security-checklist)
- [Environment Variable Management](#environment-variable-management)
- [Database Security](#database-security)
- [Rate Limiting with Cloudflare](#rate-limiting-with-cloudflare)
- [OWASP Top 10 Mitigations](#owasp-top-10-mitigations)
- [Security Monitoring](#security-monitoring)

---

## Production Security Checklist

### Pre-Deployment

- [ ] **Generate strong SECRET_KEY_BASE**
  ```bash
  docker run --rm ghcr.io/romkey/pdxhackerspace-eventmanager:latest \
    bundle exec rails secret
  ```

- [ ] **Generate strong database password**
  ```bash
  openssl rand -base64 32
  ```

- [ ] **Secure `.env` file permissions**
  ```bash
  chmod 600 .env
  chown root:root .env  # Or your deploy user
  ```

- [ ] **Enable HTTPS** (Cloudflare handles this automatically)
  - Cloudflare SSL/TLS mode: "Full (strict)" recommended
  - Force HTTPS redirects in Cloudflare

- [ ] **Configure Authentik/OAuth properly**
  - Use separate OAuth app for production
  - Whitelist only your production domain in redirect URIs
  - Keep client secret secure (never commit to git)

- [ ] **Disable debug mode**
  - Verify `RAILS_ENV=production` in docker-compose.yml
  - No `binding.pry` or `debugger` calls in code

- [ ] **Remove default credentials**
  - Change default admin password immediately after first login
  - Remove any test users from production database

- [ ] **Configure Content Security Policy** (already enabled in Rails)
  - Review `config/initializers/content_security_policy.rb`
  - Adjust if adding external scripts/styles

- [ ] **Enable security headers** (Cloudflare + Rails)
  - X-Frame-Options: DENY (prevents clickjacking)
  - X-Content-Type-Options: nosniff
  - X-XSS-Protection: 1; mode=block
  - Strict-Transport-Security (HSTS)

### Post-Deployment

- [ ] **Test authentication flows**
  - Regular login
  - OAuth login (if configured)
  - Password reset
  - Session timeout

- [ ] **Verify authorization**
  - Non-admin cannot access admin features
  - Users cannot edit others' events
  - Private events hidden from non-hosts

- [ ] **Check for exposed secrets**
  ```bash
  # Should return nothing sensitive
  curl https://yourdomain.com/health
  ```

- [ ] **Test file upload security**
  - Only images allowed for banners/favicons
  - File size limits enforced
  - Malicious files rejected

- [ ] **Enable Cloudflare security features**
  - Enable Web Application Firewall (WAF)
  - Enable DDoS protection
  - Enable Bot Fight Mode

### Monthly Security Tasks

- [ ] **Review user accounts**
  ```bash
  docker compose exec web bundle exec rails runner "
    puts 'Total users: ' + User.count.to_s
    puts 'Admins: ' + User.where(role: 'admin').count.to_s
    puts 'Recent signups: ' + User.where('created_at > ?', 1.month.ago).count.to_s
  "
  ```

- [ ] **Check for failed login attempts** (if logging enabled)
- [ ] **Review admin actions** in event journals
- [ ] **Update dependencies** (see below)
- [ ] **Review Cloudflare security events**

### Quarterly Security Tasks

- [ ] **Security audit**
  - Run `bundle audit` for gem vulnerabilities
  - Run `brakeman` for code security issues
  - Review OWASP checklist below

- [ ] **Rotate secrets**
  - Generate new SECRET_KEY_BASE
  - Update OAuth client secrets
  - Rotate database passwords

- [ ] **Review access logs**
  - Check for unusual access patterns
  - Verify geo-blocking working (if enabled)

---

## Environment Variable Management

### Critical Secrets

**Never commit these to git:**
- `SECRET_KEY_BASE`
- `DATABASE_PASSWORD`
- `AUTHENTIK_CLIENT_SECRET`
- Any API keys

### Environment File Security

**1. Secure the `.env` file:**
```bash
# Proper permissions (owner read/write only)
chmod 600 .env

# Verify
ls -la .env
# Should show: -rw------- 1 user user
```

**2. Add to `.gitignore`:**
```bash
# Already included, but verify:
grep -q "^\.env$" .gitignore || echo ".env" >> .gitignore
```

**3. Store backup securely:**
```bash
# Encrypt before storing
gpg -c .env
# Creates .env.gpg - store this in password manager or secure backup

# To decrypt later:
gpg .env.gpg
```

### Using Environment Variables in Production

**Option 1: Docker Compose .env file (simplest)**
```bash
# .env file in same directory as docker-compose.yml
DATABASE_PASSWORD=secure_password_here
SECRET_KEY_BASE=long_random_string_here
```

**Option 2: Export in shell (more secure, doesn't persist)**
```bash
# Set before running docker compose
export DATABASE_PASSWORD="secure_password"
export SECRET_KEY_BASE="long_random_string"
docker compose up -d
```

**Option 3: Docker secrets (most secure, requires Swarm)**
```yaml
# docker-compose.yml
secrets:
  db_password:
    file: ./secrets/db_password.txt

services:
  web:
    secrets:
      - db_password
```

### Rotating Secrets

**Rotate SECRET_KEY_BASE (causes all sessions to logout):**

```bash
# 1. Generate new secret
NEW_SECRET=$(docker run --rm ghcr.io/romkey/pdxhackerspace-eventmanager:latest bundle exec rails secret)

# 2. Update .env
sed -i.bak "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$NEW_SECRET/" .env

# 3. Restart services
docker compose restart web sidekiq

# 4. Notify users they need to re-login
```

**Rotate database password:**

```bash
# 1. Generate new password
NEW_DB_PASS=$(openssl rand -base64 32)

# 2. Update in PostgreSQL
docker compose exec db psql -U eventmanager -c "
  ALTER USER eventmanager WITH PASSWORD '$NEW_DB_PASS';
"

# 3. Update .env
sed -i.bak "s/^DATABASE_PASSWORD=.*/DATABASE_PASSWORD=$NEW_DB_PASS/" .env

# 4. Restart web and sidekiq
docker compose restart web sidekiq
```

### Secret Scanning

**Check for accidentally committed secrets:**

```bash
# Install gitleaks (one-time)
# brew install gitleaks  # macOS
# or download from: https://github.com/zricethezav/gitleaks

# Scan repository
gitleaks detect --source . --verbose

# Scan env templates (should contain no real secrets)
gitleaks detect --source .env.production.example --verbose
```

**If you accidentally commit a secret:**

1. **Immediately rotate the secret**
2. **Remove from git history:**
   ```bash
   # Use BFG Repo Cleaner or git filter-branch
   # See: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository
   ```
3. **Force push** (if private repo, coordinate with team)

---

## Database Security

### Connection Security

**1. Use strong password:**
```bash
# Generate secure password
openssl rand -base64 32

# Set in .env
DATABASE_PASSWORD=<strong-password-here>
```

**2. Restrict database access:**

```yaml
# docker-compose.yml - database should NOT be exposed
services:
  db:
    # No "ports:" section - only accessible within Docker network
```

**3. Use connection pooling limits:**

```yaml
# config/database.yml (already configured)
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
```

For hackerspace scale, pool size of 5 is perfect.

### Database Encryption

**Encrypt database at rest:**

```bash
# Option 1: Use encrypted Docker volume
# Requires LUKS or similar setup on host

# Option 2: Use PostgreSQL's pgcrypto for sensitive columns
docker compose exec web bundle exec rails generate migration AddEncryptionToUsers

# Add to migration:
# enable_extension 'pgcrypto'
# Add encrypted columns as needed
```

**For hackerspace:** Full database encryption probably not necessary unless handling very sensitive data.

### Connection String Security

**Never log database connection strings:**

```ruby
# config/database.yml
# Already uses ENV variables - good!
production:
  url: <%= ENV['DATABASE_URL'] %>
```

**Verify secrets not in logs:**
```bash
# Check logs don't contain passwords
docker compose logs web | grep -i password
# Should only show "password" in form fields, not actual passwords
```

### SQL Injection Prevention

EventManager uses Active Record, which **automatically prevents SQL injection** through parameterized queries.

**Safe (automatically parameterized):**
```ruby
Event.where(title: params[:title])
Event.where("title = ?", params[:title])
```

**Unsafe (never do this):**
```ruby
Event.where("title = '#{params[:title]}'")  # DON'T DO THIS
```

**Our code review:** All queries use Active Record safely. ✅

### Database Backup Security

**Encrypt backups:**

```bash
# Backup script should encrypt
pg_dump -U eventmanager EventManager_production | \
  gzip | \
  gpg -c --cipher-algo AES256 > backup_$(date +%Y%m%d).sql.gz.gpg

# Restore
gpg -d backup_20251104.sql.gz.gpg | gunzip | \
  psql -U eventmanager EventManager_production
```

**Secure backup storage:**
- Store backups on separate server/service
- Encrypt in transit (use rsync over SSH or S3 with SSL)
- Limit access to backup files (chmod 600)
- Test restores regularly

### Database User Permissions

**Principle of least privilege:**

```sql
-- Application user has necessary permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO eventmanager;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO eventmanager;

-- Application user cannot drop tables or modify schema
-- (migrations run separately with elevated permissions)
```

**For hackerspace:** Using single database user is fine. Not necessary to split read/write users.

---

## Rate Limiting with Cloudflare

Since you're behind Cloudflare, use Cloudflare's built-in rate limiting instead of application-level rate limiting.

### Cloudflare Rate Limiting Rules

**Login to Cloudflare Dashboard → Security → WAF → Rate limiting rules**

**Recommended rules for hackerspace:**

**1. Login Protection:**
```
Rule name: Protect Login
If: URI Path equals /users/sign_in AND Request Method equals POST
Then: Block for 1 hour
Requests: 5 requests per 10 minutes per IP
Mitigation: Challenge (Managed Challenge)
```

**2. API Protection:**
```
Rule name: API Rate Limit  
If: URI Path starts with /events.json OR URI Path starts with /calendar.json
Then: Block for 5 minutes
Requests: 60 requests per minute per IP
Mitigation: Block
```

**3. Form Submission Protection:**
```
Rule name: Form Spam Protection
If: Request Method equals POST
Then: Challenge
Requests: 30 requests per minute per IP
Mitigation: Challenge (Managed Challenge)
```

**4. Admin Protection (aggressive):**
```
Rule name: Admin Protection
If: URI Path starts with /admin OR URI Path equals /sidekiq
Then: Block for 1 hour
Requests: 10 requests per minute per IP
Mitigation: Block
```

### Cloudflare Security Settings

**Recommended configuration:**

**Security Level:** Medium (or High if getting attacked)
- Dashboard → Security → Settings → Security Level

**Challenge Passage:** 30 minutes
- How long a passed challenge is remembered

**Browser Integrity Check:** On
- Blocks requests without valid browser characteristics

**Enable Bot Fight Mode:** On (free plan)
- Automatically fights bot traffic

**Enable DDoS Protection:** On (automatic)

### Testing Rate Limits

**Test your rate limit configuration:**

```bash
# Test API rate limit (should trigger after 60 requests)
for i in {1..65}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://yourdomain.com/events.json
  sleep 0.5
done

# Should see 200s, then 429 (Too Many Requests) or challenge page
```

**Monitor rate limit events:**
- Cloudflare Dashboard → Security → Events
- View blocked/challenged requests in real-time

### IP Allowlisting

**Whitelist your hackerspace's IP:**

```
Cloudflare → Security → WAF → Tools → IP Access Rules
Add rule:
  Value: your.hackerspace.ip.address
  Action: Allow
  Zone: This website
```

This bypasses rate limits for requests from your space.

### Geographic Restrictions (Optional)

**If your hackerspace is regional:**

```
Cloudflare → Security → WAF → Custom rules
Create rule:
  If: Country is not in [US, CA, MX]  # Adjust as needed
  Then: Challenge (Managed Challenge)
```

**For most hackerspaces:** Not necessary unless you're getting international spam.

### Application-Level Rate Limiting (Not Needed)

Since Cloudflare handles rate limiting, **you don't need Rack::Attack or similar gems**.

Benefits of Cloudflare rate limiting:
- Happens before requests reach your server
- No application performance impact
- Protects against DDoS at network edge
- Free on all Cloudflare plans

---

## OWASP Top 10 Mitigations

### 1. Broken Access Control ✅

**Mitigations in place:**
- ✅ **Pundit authorization** on all sensitive actions
- ✅ **before_action callbacks** verify authentication
- ✅ **Policy-based** event visibility (public/members/private)
- ✅ **Admin-only routes** protected with authentication

**Verification:**
```bash
# Test unauthorized access (should fail)
curl https://yourdomain.com/events/1/edit
# Should redirect to login

# Test admin access as non-admin (should fail)
curl https://yourdomain.com/sidekiq
# Should redirect or show 403
```

**Test cases:** ✅ All passing in `spec/policies/`

---

### 2. Cryptographic Failures ✅

**Mitigations:**
- ✅ **HTTPS enforced** (Cloudflare)
- ✅ **bcrypt password hashing** (Devise default, cost: 12)
- ✅ **Secure session cookies** (encrypted, HTTP-only)
- ✅ **SECRET_KEY_BASE** for session encryption
- ✅ **No sensitive data in logs** (filtered by Rails)

**Verification:**
```bash
# Check password hashing
docker compose exec web bundle exec rails runner "
  user = User.first
  puts 'Password encrypted: ' + user.encrypted_password[0..20] + '...'
  puts 'Uses bcrypt: ' + (user.encrypted_password.start_with?('$2a$') ? 'Yes' : 'No')
"
```

**Additional hardening:**
```ruby
# config/initializers/filter_parameter_logging.rb (already configured)
Rails.application.config.filter_parameters += [
  :password, :password_confirmation, :secret, :token
]
```

---

### 3. Injection ✅

**SQL Injection Prevention:**
- ✅ **Active Record ORM** (parameterized queries)
- ✅ **No raw SQL** with user input
- ✅ **Strong parameters** for mass assignment protection

**XSS Prevention:**
- ✅ **Auto-escaped ERB templates** (Rails default)
- ✅ **sanitize()** helper for user-generated HTML
- ✅ **Content Security Policy** configured

**Verification:**
```bash
# Review all raw SQL usage (should be minimal/none with user input)
grep -r "execute\|find_by_sql" app/

# Review all html_safe usage (should be minimal)
grep -r "html_safe\|raw(" app/
```

**Code review:** ✅ All queries use Active Record safely.

---

### 4. Insecure Design ✅

**Security designed in:**
- ✅ **Authentication required** for write operations
- ✅ **Authorization checked** before sensitive actions
- ✅ **Event visibility** controls access
- ✅ **CSRF protection** enabled (Rails default)
- ✅ **Session timeout** configured (Devise)
- ✅ **Password complexity** enforced (Devise default: 6 chars min)

**Improvements (optional):**

```ruby
# config/initializers/devise.rb
# Increase password minimum length
config.password_length = 12..128

# Expire sessions after inactivity
config.timeout_in = 24.hours

# Lock account after failed login attempts
config.lock_strategy = :failed_attempts
config.maximum_attempts = 5
config.unlock_in = 1.hour
```

---

### 5. Security Misconfiguration ✅

**Rails security defaults enabled:**
- ✅ **CSRF protection** enabled
- ✅ **Secure headers** set
- ✅ **Force SSL** in production (Cloudflare)
- ✅ **Debug mode** disabled in production
- ✅ **Error pages** don't expose stack traces in production

**Docker security:**
- ✅ **Non-root user** in containers (runs as user 1000)
- ✅ **Minimal base image** (ruby:3.2.2)
- ✅ **No unnecessary packages** installed
- ✅ **Secrets in .env**, not in image

**Verification:**
```bash
# Check security headers
curl -I https://yourdomain.com | grep -E '(X-Frame|X-Content|Strict-Transport)'

# Should see:
# X-Frame-Options: DENY
# X-Content-Type-Options: nosniff  
# Strict-Transport-Security: max-age=31536000
```

---

### 6. Vulnerable and Outdated Components 🔄

**Current versions:**
- Ruby: 3.2.2 ✅ (supported until 2026)
- Rails: 7.1.6 ✅ (latest stable)
- PostgreSQL: 14 ✅ (supported until 2026)
- Redis: 7 ✅ (latest)
- Node: 20.x LTS ✅ (supported until 2026)

**Monitoring for vulnerabilities:**

```bash
# Check for gem vulnerabilities (run monthly)
docker compose exec web bundle audit check --update

# Check for JavaScript vulnerabilities  
docker compose exec web yarn audit

# Automated scanning (already in CI/CD)
# - Trivy scans Docker images
# - GitHub Dependabot enabled
```

**Update process:**

```bash
# Update gems (test in development first)
docker compose exec web bundle update
docker compose exec web bundle audit check

# Update JavaScript packages
docker compose exec web yarn upgrade
docker compose exec web yarn audit

# Commit changes
git add Gemfile.lock package.json yarn.lock
git commit -m "chore: update dependencies"

# Deploy with normal deployment process
```

**Subscribe to security advisories:**
- Ruby: https://www.ruby-lang.org/en/security/
- Rails: https://rubyonrails.org/category/security
- PostgreSQL: https://www.postgresql.org/support/security/

---

### 7. Identification and Authentication Failures ✅

**Mitigations:**
- ✅ **Devise gem** for authentication (battle-tested)
- ✅ **bcrypt password hashing** (strong, slow)
- ✅ **OAuth via Authentik** (optional, SSO)
- ✅ **Session management** (encrypted cookies)
- ✅ **Password reset** with secure tokens
- ✅ **Remember me** with separate token

**Additional hardening (optional):**

```ruby
# config/initializers/devise.rb

# Expire password reset tokens quickly
config.reset_password_within = 2.hours

# Expire confirmation tokens
config.confirm_within = 3.days

# Pepper for additional password security
config.pepper = ENV['DEVISE_PEPPER']  # Add to .env
```

**Multi-factor authentication (future enhancement):**
```ruby
# Add gem 'devise-two-factor' for 2FA
# Recommended for admin accounts in future versions
```

---

### 8. Software and Data Integrity Failures ✅

**Mitigations:**
- ✅ **Docker image signatures** (GitHub Container Registry)
- ✅ **Dependency pinning** (Gemfile.lock, yarn.lock)
- ✅ **Trivy scanning** in CI/CD
- ✅ **Git commit signing** (recommended)
- ✅ **CI/CD pipeline** verifies tests before deployment

**Verify Docker image:**
```bash
# Check image signature (if using signed images)
docker trust inspect ghcr.io/romkey/pdxhackerspace-eventmanager:latest

# Check image for known vulnerabilities
docker run --rm aquasec/trivy image \
  ghcr.io/romkey/pdxhackerspace-eventmanager:latest
```

**Code integrity:**
```bash
# Enable git commit signing (recommended)
git config --global commit.gpgsign true
git config --global user.signingkey YOUR_GPG_KEY

# Verify commits
git log --show-signature
```

---

### 9. Security Logging and Monitoring Failures 🔄

**Current logging:**
- ✅ **Rails logs** (production.log)
- ✅ **Nginx/Puma access logs**
- ✅ **Event journal** (audit trail for events)
- ✅ **Sidekiq job logs**

**What to log (already configured):**
- ✅ Authentication events (Devise)
- ✅ Authorization failures (Pundit)
- ✅ Event creation/modification (EventJournal)
- ✅ Background job execution (Sidekiq)

**Improvements needed:**

```ruby
# config/environments/production.rb
# Add logging of security events

# Log authentication events
ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  if event.payload[:controller] == 'Devise::SessionsController'
    Rails.logger.warn("[SECURITY] Login attempt: #{event.payload.inspect}")
  end
end
```

**Monitoring recommendations:**

1. **Cloudflare Security Events** - Review weekly
2. **Docker logs** - Check for errors daily
3. **Sidekiq failed jobs** - Check daily at /sidekiq
4. **Event journal** - Review admin actions weekly

**Set up log rotation:**
```bash
# /etc/logrotate.d/eventmanager
/path/to/eventmanager/log/*.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
}
```

---

### 10. Server-Side Request Forgery (SSRF) ✅

**Attack vectors in EventManager:**

1. **Event more_info_url** - User-provided URL
   - ✅ **Validation:** Requires http/https protocol
   - ✅ **Not fetched server-side** - only displayed as link
   - ✅ **Safe:** No SSRF risk

2. **Banner/favicon uploads** - Image files
   - ✅ **Active Storage** validates content type
   - ✅ **No server-side fetching** of URLs
   - ✅ **Safe:** No SSRF risk

3. **OAuth callback URLs**
   - ✅ **Whitelist in Authentik** configuration
   - ✅ **Safe:** Controlled by admin

**Code review:** ✅ No SSRF vulnerabilities found.

**If adding URL fetching features:**
```ruby
# Use allowlist approach
ALLOWED_HOSTS = ['example.com', 'trusted-site.org']

def fetch_url(url)
  uri = URI.parse(url)
  raise 'Invalid protocol' unless ['http', 'https'].include?(uri.scheme)
  raise 'Host not allowed' unless ALLOWED_HOSTS.include?(uri.host)
  
  # Fetch with timeout
  Net::HTTP.get_response(uri)
end
```

---

## Security Monitoring

### Daily Checks (automated if possible)

```bash
#!/bin/bash
# save as /usr/local/bin/security-check.sh

echo "=== Security Health Check ==="
echo "Date: $(date)"

# Check for failed authentication
echo -e "\n--- Failed Logins (last 24h) ---"
docker compose exec web grep -i "unauthorized\|401\|403" log/production.log | \
  grep -i "$(date +%Y-%m-%d)" | wc -l

# Check Sidekiq job failures
echo -e "\n--- Failed Jobs ---"
docker compose exec web bundle exec rails runner "
  failed = Sidekiq::RetrySet.new.size
  dead = Sidekiq::DeadSet.new.size
  puts \"Retry queue: #{failed}\"
  puts \"Dead queue: #{dead}\"
  puts \"⚠️  Check /sidekiq for details\" if failed + dead > 0
"

# Check disk space
echo -e "\n--- Disk Usage ---"
df -h / | grep -v Filesystem

# Check container health
echo -e "\n--- Container Health ---"
docker compose ps | grep -E '(unhealthy|Exit)'

echo -e "\n=== End Security Check ==="
```

### Weekly Reviews

- Review Cloudflare security events
- Check for new CVEs affecting dependencies
- Review admin activity in event journal
- Check for unusual user account growth

### Monthly Audits

- Run `bundle audit` for gem vulnerabilities
- Run `brakeman` for code security issues
- Review and update this security checklist
- Test backup restoration
- Review rate limit effectiveness

### Incident Response

**If you suspect a security incident:**

1. **Assess severity** - Is it ongoing? Data breach? Service disruption?
2. **Contain** - Block malicious IPs in Cloudflare
3. **Investigate** - Review logs, identify scope
4. **Remediate** - Patch vulnerability, rotate secrets
5. **Document** - Record timeline and actions taken
6. **Learn** - Update procedures to prevent recurrence

**Emergency contacts:** See OPERATIONS.md

---

## Additional Resources

- [Rails Security Guide](https://guides.rubyonrails.org/security.html)
- [OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/)
- [Cloudflare Security Center](https://www.cloudflare.com/learning/security/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)


