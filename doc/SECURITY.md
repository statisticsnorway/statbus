# StatBus Security

This document describes the security model of StatBus for IT decision makers and operators.

## Executive Summary

StatBus protects its upgrade pipeline with **cryptographic commit signing** using SSH keys. Every code change is signed by an authorized developer. Every installation verifies signatures locally before executing upgrades. No code runs without mathematical proof of authorship.

Authentication uses **JWT tokens mapped to PostgreSQL roles** with Row Level Security (RLS). The database enforces access control — there is no application-level bypass.

## How Upgrades Work

1. A developer signs a commit with their SSH key and pushes to GitHub
2. CI builds Docker images and publishes a release with binary artifacts
3. Each installation's upgrade daemon discovers new releases via `git fetch` (no API dependency)
4. The daemon verifies the commit signature against locally-stored trusted keys
5. If verified: backup database, pull images, apply migrations, restart services
6. If verification fails: the upgrade is rejected and logged

The entire verification happens locally on each installation. No external service is consulted at runtime.

## Trust Model

### Who Can Publish Releases

Only developers whose SSH public keys are stored in the installation's `.env.config` file. The configuration key pattern is `UPGRADE_TRUSTED_SIGNER_<name>`.

### How Trust Is Established

During installation (`./sb install`), the operator is prompted to approve trusted signers. The installer recommends the project maintainer (jhf) and fetches their SSH public key from GitHub. The operator must explicitly confirm by reviewing the key fingerprint.

No key is trusted without human confirmation. The installation will not accept unsigned upgrades.

### Adding and Removing Signers

```bash
./sb upgrade trust-key add <github-username>   # fetch key, confirm fingerprint, store
./sb upgrade trust-key remove <name>           # revoke trust
./sb upgrade trust-key list                    # show all trusted signers
./sb upgrade trust-key verify                  # test that verification works
```

Keys are stored in `.env.config` and verified locally. GitHub is only contacted during `trust-key add` — never at runtime.

## What Is Protected

| Threat | Defense |
|--------|---------|
| Compromised GitHub repository | Commits must be signed by a trusted key |
| Compromised CI pipeline | CI builds images but cannot forge commit signatures |
| Man-in-the-middle on git fetch | Commit signatures are verified locally against trusted keys |
| Unauthorized releases | Only commits signed by trusted keys are accepted |
| Downgrade attacks | Version comparison prevents installing older releases |
| Interrupted upgrades | Automatic database backup and rollback on failure |

## What Is NOT Protected

**Local server compromise**: Anyone with write access to `.env.config` can add trusted signers. This is by design — local security is the operator's responsibility. StatBus protects the supply chain from the developer's machine to the server. Local server hardening (firewalls, SSH keys, file permissions) is the operator's domain.

## Authentication and Authorization

StatBus uses **JWT-based authentication** with **PostgreSQL Row Level Security (RLS)**.

### Architecture

- **PostgREST** serves the REST API directly from the database schema
- **JWT tokens** contain the user's role and are verified against a secret stored in the database
- **RLS policies** on every table enforce who can see and modify which rows
- **Role hierarchy**: `admin_user > regular_user > restricted_user > external_user`

### Security Properties

- The JWT secret is stored in an RLS-protected table (`auth.secrets`) — inaccessible via direct SQL
- Role switching (`auth.jwt_switch_role`) is called before any transaction begins, preventing ROLLBACK attacks
- SECURITY DEFINER functions are registered and audited (test 008 verifies the complete list)
- All API routes that use direct database connections follow the secure pattern: role switch → begin → operate → commit

### Independent Review Result

The JWT auth system was independently reviewed and found **SECURE** across all checks:
- ROLLBACK attack resistance: verified
- Role escalation prevention: verified
- Token forgery protection: verified
- PostgREST bypass resistance: verified
- SQL injection protection: verified

## Application Isolation

The Next.js application has **no elevated database access**. It connects to PostgREST using the same JWT tokens as any external API consumer. There is no server-side database password, no admin connection string, no backdoor.

This means:

- **A compromised application cannot escalate privileges.** Even if an attacker gains full control of the Next.js process, they can only make requests as the currently authenticated user. The database enforces Row Level Security on every query.

- **SQL injection is contained.** In the unlikely event of a SQL injection vulnerability in an API route, the injected SQL executes with the authenticated user's permissions — not as a database superuser. The attacker cannot access other users' data, modify system tables, or bypass RLS policies.

- **The database is the security boundary, not the application.** PostgREST validates JWT tokens and switches to the user's database role before executing any query. The application is a thin client that formats requests and renders responses. Security does not depend on application logic being correct.

This architecture is fundamentally different from traditional applications where the backend connects to the database with a shared privileged credential. In StatBus, there is no shared credential to steal.

The only exceptions are two performance-optimized API routes (`/api/import/upload` and `/api/import/download`) that use direct PostgreSQL connections. These routes:
1. Authenticate via the same JWT cookie
2. Call `auth.jwt_switch_role()` to assume the user's database role **before** starting any transaction
3. Operate under the same RLS policies as PostgREST

## Key Management Procedures

### Adding a New Signer

```bash
./sb upgrade trust-key add <github-username>
```

The command fetches the user's SSH key from GitHub, displays the fingerprint, and asks for confirmation. The key is then stored permanently in `.env.config`.

### Revoking a Signer

```bash
./sb upgrade trust-key remove <name>
```

Immediately effective. The next discovery cycle will reject any commits signed only by the revoked key.

### Key Compromise Playbook

1. Remove the compromised key: `./sb upgrade trust-key remove <name>` on all servers
2. Audit: check recent upgrades for commits signed by the compromised key
3. If suspicious commits found: restore from backup (`./sb db backup restore <name>`)
4. Revoke the key on GitHub (rotate the developer's SSH key)
5. Re-add the developer with their new key: `./sb upgrade trust-key add <username>`

### Handoff Procedure

If the primary signer becomes unavailable:

1. A new signer sets up commit signing: `./dev.sh setup-signing`
2. An operator with server access adds them: `./sb upgrade trust-key add <new-username>`
3. The new signer can now make releases that all installations will accept

No central authority is needed. Each installation independently decides who to trust.

## Disk Space Monitoring

The upgrade daemon monitors available disk space and reports it in the admin UI:
- **Above 10 GB**: normal operation
- **Below 10 GB**: warning displayed — upgrades may fail
- **Below 5 GB**: critical alert — upgrades are blocked, contact IT

The installation process requires at least 100 GB of free space.

## Edge Channel

The edge channel tracks every commit on master, not just tagged releases. Commit signatures are verified the same way as tagged releases — there is no security exception. Edge is intended for development servers that need to test the latest code.

## Prerequisites

- Git 2.34+ (for SSH signing support)
- SSH key pair (ed25519 recommended)
- Docker and Docker Compose
