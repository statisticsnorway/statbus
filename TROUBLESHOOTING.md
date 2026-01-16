# STATBUS Troubleshooting Guide

## Production Testing Issues

### ❌ DON'T: Use `pnpm run prod-local` for production issue testing

If you run `pnpm run prod-local` and test at `http://localhost:3001`, you'll encounter:

**CORS Errors:**
```
Access to fetch at 'http://local.statbus.org:3010/rest/rpc/auth_status' from origin 'http://localhost:3001' has been blocked by CORS policy
```

**Why this happens:**
- App runs on `localhost:3001` (different origin)
- API calls go to `local.statbus.org:3010` (different origin)
- Browser blocks cross-origin requests
- Next.js proxy rewrites only work in development mode
- Production builds expect unified URL architecture

### ✅ DO: Use Docker for production testing

```bash
# Stop any running app
./devops/manage-statbus.sh stop app

# Rebuild with latest changes
docker compose build app --no-cache

# Start production-like environment  
./devops/manage-statbus.sh start app

# Test at unified URL
open http://local.statbus.org:3010
```

**Why this works:**
- ✅ Uses unified URL (`local.statbus.org:3010` for everything)
- ✅ Caddy handles `/rest` API forwarding
- ✅ No CORS issues (same origin)
- ✅ Exact production architecture
- ✅ Real production builds

### Navigation Hang Issues

If you see the page stuck on "Loading application..." at `/login` after successful authentication:

**Root Cause:** Navigation deadlock between Next.js router and page rendering
- Navigation machine commands `router.push('/')`
- Root page blocks rendering on data loading
- Next.js waits for page to render before completing navigation
- Navigation machine waits for pathname change
- Deadlock occurs

**How to Test Locally:**
1. Use Docker: `./devops/manage-statbus.sh start app`
2. Open `http://local.statbus.org:3010` in browser
3. Enable debug: `localStorage.setItem('debug', 'true')`  
4. Login and observe if it hangs at `/login`

**Console Logs to Watch:**
- `[DEBUG] [nav-machine:redirectingFromLogin] Redirecting away from /login to /`
- If URL stays at `/login` → bug reproduced
- If URL changes to `/` → navigation completed successfully

### Docker Container Issues

**Database Connection Issues:**
```bash
# Check all services
docker compose ps

# Should show:
# statbus-local-db     - healthy
# statbus-local-rest   - running  
# statbus-local-proxy  - running
# statbus-local-app    - running
```

**If services aren't healthy:**
```bash
# Check logs
docker compose logs db --tail=50
docker compose logs rest --tail=50
docker compose logs app --tail=50

# Restart services
./devops/manage-statbus.sh restart
```

### Environment Configuration Issues

**Missing .env file:**
```
ERROR: ../.env file not found!
Please run: ./devops/manage-statbus.sh generate-config
```

**Solution:**
```bash
./devops/manage-statbus.sh generate-config
```

**DNS resolution issues:**
```bash
# Test DNS resolution
host local.statbus.org
# Should return: local.statbus.org has address 127.0.0.1

# If not working, add to /etc/hosts:
echo "127.0.0.1 local.statbus.org" | sudo tee -a /etc/hosts
```

## Common Patterns

### Fast Development Iteration

For navigation/auth/state machine issues:

```bash
# 1. Make code changes
# 2. Rebuild container (takes ~2-3 minutes)
docker compose build app --no-cache

# 3. Start and test
./devops/manage-statbus.sh start app

# 4. Test at unified URL
open http://local.statbus.org:3010
```

### Debug State Machines

```javascript
// In browser console
localStorage.setItem('debug', 'true')
// Reload page to see detailed state machine logs
```

### Quick Health Check

```bash
# Test if app responds
curl -I http://local.statbus.org:3010/

# Should return:
# HTTP/1.1 200 OK  (or 307 redirect to /login)
```

## When to Use Which Testing Method

| Issue Type | Use | Access URL |
|------------|-----|------------|
| Navigation, auth, state machines | Docker | `http://local.statbus.org:3010` |
| API calls, data loading | Docker | `http://local.statbus.org:3010` |
| Production build verification | Docker | `http://local.statbus.org:3010` |
| Bundle size analysis | Either | `localhost:3001` or `local.statbus.org:3010` |
| Quick build test | `pnpm run prod-local` | `http://localhost:3001` |
| Development | `pnpm run dev` | `http://localhost:3000` |

## Remember: Docker for Real Production Testing

The key insight is that STATBUS uses a **unified URL architecture** in production:
- Single domain handles both app and API
- Caddy proxy routes `/rest/*` to PostgREST
- This eliminates CORS issues and matches production exactly

When testing production issues, always use Docker to get this architecture right.