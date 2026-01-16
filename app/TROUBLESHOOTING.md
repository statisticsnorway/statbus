# TROUBLESHOOTING GUIDE

## Production Testing Anti-Patterns

### ❌ DON'T: Use `pnpm run prod-local` for production issue testing

**Problem**: CORS errors and broken API calls
```
Access to fetch at 'http://local.statbus.org:3010/rest/rpc/auth_status' 
from origin 'http://localhost:3001' has been blocked by CORS policy
```

**Why it happens**:
- Production builds expect unified URLs (same origin for app and API)
- Caddy proxy handles `/rest` forwarding in production
- `pnpm run prod-local` creates cross-origin requests
- Next.js development proxy rewrites are disabled in production

**Common symptoms**:
- Authentication fails immediately
- Navigation hangs on "Loading application..."
- Console shows CORS policy errors
- API requests return `net::ERR_FAILED`

### ✅ DO: Use Docker for production testing

```bash
./devops/manage-statbus.sh stop app
docker compose build app --no-cache
./devops/manage-statbus.sh start app

# Test at: http://local.statbus.org:3010
```

**Why this works**:
- Exact production environment (container networking)
- Unified URL architecture (Caddy handles routing)
- Same build process and runtime as production
- No CORS issues

## Common Production Issues

### Navigation Hang After Login

**Symptoms**:
- Login succeeds but page stuck on "Loading application..."
- URL stays at `/login` instead of redirecting
- Console shows `nav-machine:redirectingFromLogin` but no completion

**Root cause**: Navigation deadlock between Next.js router and page rendering
- Navigation machine triggers `router.push('/')`
- Root page blocks on `isReadyToRenderDashboard`
- Next.js waits for page render before completing navigation
- Machine waits for pathname change
- **Deadlock**

**Testing approach**:
1. Use Docker setup (not `pnpm run prod-local`)
2. Enable debug: `localStorage.setItem('debug', 'true')`
3. Clear cookies and test fresh login
4. Monitor console for state machine logs

### Authentication Failures

**Symptoms**:
- Immediate auth failures
- JSON parsing errors in console
- Empty auth responses

**Common causes**:
- CORS issues (using wrong testing setup)
- Environment variable mismatches
- PostgREST connection problems
- Docker networking issues

**Debug steps**:
1. Verify Docker containers running: `docker compose ps`
2. Check network connectivity: `curl http://local.statbus.org:3010/rest/rpc/auth_status`
3. Inspect container logs: `docker compose logs app`

### Development vs Production Differences

**Environment-specific issues**:
- Data loading timing differences
- Code splitting behavior changes
- Build optimization effects
- Container networking vs host networking

**Testing matrix**:
- ✅ Development: `pnpm run dev` (for development issues)
- ✅ Production: Docker setup (for production issues)
- ❌ Never use: `pnpm run prod-local` (for production API testing)

## Quick Reference

### Start Docker App for Production Testing
```bash
./devops/manage-statbus.sh start app
# Access: http://local.statbus.org:3010
```

### Rebuild Docker App After Code Changes
```bash
./devops/manage-statbus.sh stop app
docker compose build app --no-cache
./devops/manage-statbus.sh start app
```

### Check Container Status
```bash
docker compose ps
docker compose logs app --tail=50
```

### Enable Debug Logging
```javascript
// In browser console
localStorage.setItem('debug', 'true')
// Refresh page to see detailed state machine logs
```

## Architecture Reminder

**Production URL Architecture**:
- Single origin: `https://statbus.example.com`
- App serves on `/`
- API serves on `/rest/*` (proxied by Caddy)
- No CORS issues (same origin)

**Local Development**:
- App: `http://localhost:3000`
- API: `http://localhost:3000/rest/*` (proxied by Next.js)
- No CORS issues (proxied)

**Local Production Testing**:
- App: `http://local.statbus.org:3010`
- API: `http://local.statbus.org:3010/rest/*` (proxied by Caddy)
- No CORS issues (unified URL)

**BROKEN: pnpm run prod-local**:
- App: `http://localhost:3001`
- API: `http://local.statbus.org:3010/rest/*` (different origin)
- ❌ CORS issues (cross-origin requests)

## Memory Aid

When you see CORS errors or API failures in production testing:

1. **STOP** - You're probably using `pnpm run prod-local`
2. **SWITCH** - Use Docker: `./devops/manage-statbus.sh start app`
3. **TEST** - Access `http://local.statbus.org:3010`

Remember: **Unified URL = No CORS issues**