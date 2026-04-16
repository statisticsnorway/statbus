```sql
                                                                                                                                                                                              Table "public.upgrade"
          Column          |           Type           | Collation | Nullable |            Default            | Storage  | Compression | Stats target |                                                                                                                         Description                                                                                                                          
--------------------------+--------------------------+-----------+----------+-------------------------------+----------+-------------+--------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 id                       | integer                  |           | not null | generated always as identity  | plain    |             |              | 
 commit_sha               | text                     |           | not null |                               | extended |             |              | 
 committed_at             | timestamp with time zone |           | not null |                               | plain    |             |              | 
 topological_order        | integer                  |           |          |                               | plain    |             |              | 
 tags                     | text[]                   |           | not null | '{}'::text[]                  | extended |             |              | 
 release_status           | release_status_type      |           | not null | 'commit'::release_status_type | plain    |             |              | 
 summary                  | text                     |           | not null |                               | extended |             |              | 
 changes                  | text                     |           |          |                               | extended |             |              | 
 release_url              | text                     |           |          |                               | extended |             |              | 
 has_migrations           | boolean                  |           | not null | false                         | plain    |             |              | 
 discovered_at            | timestamp with time zone |           | not null | clock_timestamp()             | plain    |             |              | 
 scheduled_at             | timestamp with time zone |           |          |                               | plain    |             |              | 
 started_at               | timestamp with time zone |           |          |                               | plain    |             |              | 
 completed_at             | timestamp with time zone |           |          |                               | plain    |             |              | 
 error                    | text                     |           |          |                               | extended |             |              | 
 rolled_back_at           | timestamp with time zone |           |          |                               | plain    |             |              | 
 skipped_at               | timestamp with time zone |           |          |                               | plain    |             |              | 
 from_version             | text                     |           |          |                               | extended |             |              | 
 docker_images_downloaded | boolean                  |           | not null | false                         | plain    |             |              | 
 backup_path              | text                     |           |          |                               | extended |             |              | 
 superseded_at            | timestamp with time zone |           |          |                               | plain    |             |              | 
 docker_images_ready      | boolean                  |           | not null | false                         | plain    |             |              | Docker images (db/app/worker/proxy) exist in the registry at the runtime VERSION tag. Set by the upgrade service discovery cycle via docker manifest inspect.
 release_builds_ready     | boolean                  |           | not null | false                         | plain    |             |              | Release builds (sb binary + manifest.json + GitHub Release entry) exist for a tagged release. Commits have this pre-set true since edge channel does not need release builds.
 dismissed_at             | timestamp with time zone |           |          |                               | plain    |             |              | Timestamp when the operator dismissed (acknowledged) a failed or rolled_back upgrade. Distinct from skipped_at, which is for available upgrades the user chose not to apply.
 state                    | upgrade_state            |           | not null | 'available'::upgrade_state    | plain    |             |              | Authoritative upgrade lifecycle state. Code writes this explicitly on every transition. The chk_upgrade_state_attributes CHECK constraint validates that the timestamp columns match the declared state — illegal combinations are rejected at the DB layer.
 version                  | text                     |           |          |                               | extended |             |              | Output of `git describe --tags --always <commit_sha>` captured at discovery time. Used by the upgrade service to look up Docker images in GHCR without drift caused by later tags being pushed past the commit.
 log_relative_file_path   | text                     |           |          |                               | extended |             |              | Basename of the per-upgrade log file under tmp/upgrade-logs/. Populated by the upgrade service at start. Superseded progress_log (to be dropped once the UI migrates to fetching /upgrade-logs/<name>).
Indexes:
    "upgrade_pkey" PRIMARY KEY, btree (id)
    "upgrade_commit_sha_key" UNIQUE CONSTRAINT, btree (commit_sha)
Check constraints:
    "chk_upgrade_commit_sha_is_full_hex" CHECK (commit_sha ~ '^[a-f0-9]{40}$'::text)
    "chk_upgrade_state_attributes" CHECK (
CASE state
    WHEN 'available'::upgrade_state THEN scheduled_at IS NULL AND started_at IS NULL AND completed_at IS NULL AND error IS NULL AND rolled_back_at IS NULL AND skipped_at IS NULL AND dismissed_at IS NULL AND superseded_at IS NULL
    WHEN 'scheduled'::upgrade_state THEN scheduled_at IS NOT NULL AND started_at IS NULL AND completed_at IS NULL AND error IS NULL AND rolled_back_at IS NULL
    WHEN 'in_progress'::upgrade_state THEN scheduled_at IS NOT NULL AND started_at IS NOT NULL AND completed_at IS NULL AND error IS NULL AND rolled_back_at IS NULL
    WHEN 'completed'::upgrade_state THEN completed_at IS NOT NULL AND error IS NULL AND rolled_back_at IS NULL
    WHEN 'failed'::upgrade_state THEN error IS NOT NULL AND started_at IS NOT NULL AND completed_at IS NULL AND rolled_back_at IS NULL
    WHEN 'rolled_back'::upgrade_state THEN rolled_back_at IS NOT NULL AND error IS NOT NULL AND completed_at IS NULL
    WHEN 'dismissed'::upgrade_state THEN dismissed_at IS NOT NULL AND (error IS NOT NULL OR rolled_back_at IS NOT NULL)
    WHEN 'skipped'::upgrade_state THEN skipped_at IS NOT NULL
    WHEN 'superseded'::upgrade_state THEN superseded_at IS NOT NULL
    ELSE false
END)
Policies:
    POLICY "upgrade_admin_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "upgrade_authenticated_view" FOR SELECT
      TO authenticated
      USING (true)
Not-null constraints:
    "upgrade_id_not_null" NOT NULL "id"
    "upgrade_commit_sha_not_null" NOT NULL "commit_sha"
    "upgrade_committed_at_not_null" NOT NULL "committed_at"
    "upgrade_tags_not_null" NOT NULL "tags"
    "upgrade_release_status_not_null" NOT NULL "release_status"
    "upgrade_summary_not_null" NOT NULL "summary"
    "upgrade_has_migrations_not_null" NOT NULL "has_migrations"
    "upgrade_discovered_at_not_null" NOT NULL "discovered_at"
    "upgrade_images_downloaded_not_null" NOT NULL "docker_images_downloaded"
    "upgrade_docker_images_ready_not_null" NOT NULL "docker_images_ready"
    "upgrade_release_builds_ready_not_null" NOT NULL "release_builds_ready"
    "upgrade_state_not_null" NOT NULL "state"
Triggers:
    upgrade_notify_daemon_trigger AFTER UPDATE ON upgrade FOR EACH ROW EXECUTE FUNCTION upgrade_notify_daemon()
    upgrade_notify_frontend_trigger AFTER INSERT OR DELETE OR UPDATE ON upgrade FOR EACH ROW EXECUTE FUNCTION upgrade_notify_frontend()
Access method: heap

```
