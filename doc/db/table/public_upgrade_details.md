```sql
                                                                                                                                                                                                                                   Table "public.upgrade"
          Column          |            Type            | Collation | Nullable |                Default                 | Storage  | Compression | Stats target |                                                                                                                                                        Description                                                                                                                                                         
--------------------------+----------------------------+-----------+----------+----------------------------------------+----------+-------------+--------------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 id                       | integer                    |           | not null | generated always as identity           | plain    |             |              | 
 commit_sha               | text                       |           | not null |                                        | extended |             |              | 
 committed_at             | timestamp with time zone   |           | not null |                                        | plain    |             |              | 
 topological_order        | integer                    |           |          |                                        | plain    |             |              | 
 commit_tags              | text[]                     |           | not null | '{}'::text[]                           | extended |             |              | 
 release_status           | release_status_type        |           | not null | 'commit'::release_status_type          | plain    |             |              | 
 summary                  | text                       |           | not null |                                        | extended |             |              | 
 changes                  | text                       |           |          |                                        | extended |             |              | 
 release_url              | text                       |           |          |                                        | extended |             |              | 
 has_migrations           | boolean                    |           | not null | false                                  | plain    |             |              | 
 discovered_at            | timestamp with time zone   |           | not null | clock_timestamp()                      | plain    |             |              | 
 scheduled_at             | timestamp with time zone   |           |          |                                        | plain    |             |              | 
 started_at               | timestamp with time zone   |           |          |                                        | plain    |             |              | 
 completed_at             | timestamp with time zone   |           |          |                                        | plain    |             |              | 
 error                    | text                       |           |          |                                        | extended |             |              | 
 rolled_back_at           | timestamp with time zone   |           |          |                                        | plain    |             |              | 
 skipped_at               | timestamp with time zone   |           |          |                                        | plain    |             |              | 
 from_commit_version      | text                       |           |          |                                        | extended |             |              | 
 docker_images_downloaded | boolean                    |           | not null | false                                  | plain    |             |              | 
 backup_path              | text                       |           |          |                                        | extended |             |              | 
 superseded_at            | timestamp with time zone   |           |          |                                        | plain    |             |              | 
 dismissed_at             | timestamp with time zone   |           |          |                                        | plain    |             |              | Timestamp when the operator dismissed (acknowledged) a failed or rolled_back upgrade. Distinct from skipped_at, which is for available upgrades the user chose not to apply.
 state                    | upgrade_state              |           | not null | 'available'::upgrade_state             | plain    |             |              | Authoritative upgrade lifecycle state. Code writes this explicitly on every transition. The chk_upgrade_state_attributes CHECK constraint validates that the timestamp columns match the declared state — illegal combinations are rejected at the DB layer.
 commit_version           | text                       |           |          |                                        | extended |             |              | Output of `git describe --tags --always <commit_sha>` captured at discovery time. Used by the upgrade service to look up Docker images in GHCR without drift caused by later tags being pushed past the commit.
 log_relative_file_path   | text                       |           |          |                                        | extended |             |              | Basename of the per-upgrade log file under tmp/upgrade-logs/. Populated by the upgrade service at start. Superseded progress_log (to be dropped once the UI migrates to fetching /upgrade-logs/<name>).
 docker_images_status     | docker_images_status_type  |           | not null | 'building'::docker_images_status_type  | plain    |             |              | Docker image build status: building (CI in progress), ready (images verified in registry), failed (CI workflow failed). Checked by the upgrade service via docker manifest inspect and GitHub Actions API.
 release_builds_status    | release_builds_status_type |           | not null | 'building'::release_builds_status_type | plain    |             |              | Release build status: building (release.yaml in progress), ready (GitHub Release + sb binary + manifest verified), failed (release workflow failed). For commits (edge channel) this defaults to ready since edge does not use release artifacts. Checked by the upgrade service via FetchManifest and GitHub Actions API.
Indexes:
    "upgrade_pkey" PRIMARY KEY, btree (id)
    "upgrade_commit_sha_key" UNIQUE CONSTRAINT, btree (commit_sha)
    "upgrade_single_in_progress" UNIQUE, btree (state) WHERE state = 'in_progress'::upgrade_state
    "upgrade_single_scheduled" UNIQUE, btree (state) WHERE state = 'scheduled'::upgrade_state
Check constraints:
    "chk_upgrade_commit_sha_is_full_hex" CHECK (commit_sha ~ '^[a-f0-9]{40}$'::text)
    "chk_upgrade_state_attributes" CHECK (
CASE state
    WHEN 'available'::upgrade_state THEN scheduled_at IS NULL AND started_at IS NULL AND completed_at IS NULL AND rolled_back_at IS NULL AND skipped_at IS NULL AND dismissed_at IS NULL AND superseded_at IS NULL
    WHEN 'scheduled'::upgrade_state THEN scheduled_at IS NOT NULL AND started_at IS NULL AND completed_at IS NULL AND rolled_back_at IS NULL
    WHEN 'in_progress'::upgrade_state THEN scheduled_at IS NOT NULL AND started_at IS NOT NULL AND completed_at IS NULL AND rolled_back_at IS NULL
    WHEN 'completed'::upgrade_state THEN completed_at IS NOT NULL AND error IS NULL AND rolled_back_at IS NULL AND log_relative_file_path IS NOT NULL
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
    "upgrade_tags_not_null" NOT NULL "commit_tags"
    "upgrade_release_status_not_null" NOT NULL "release_status"
    "upgrade_summary_not_null" NOT NULL "summary"
    "upgrade_has_migrations_not_null" NOT NULL "has_migrations"
    "upgrade_discovered_at_not_null" NOT NULL "discovered_at"
    "upgrade_images_downloaded_not_null" NOT NULL "docker_images_downloaded"
    "upgrade_state_not_null" NOT NULL "state"
    "upgrade_docker_images_status_not_null" NOT NULL "docker_images_status"
    "upgrade_release_builds_status_not_null" NOT NULL "release_builds_status"
Triggers:
    upgrade_notify_daemon_trigger AFTER UPDATE ON upgrade FOR EACH ROW EXECUTE FUNCTION upgrade_notify_daemon()
    upgrade_notify_frontend_trigger AFTER INSERT OR DELETE OR UPDATE ON upgrade FOR EACH ROW EXECUTE FUNCTION upgrade_notify_frontend()
Access method: heap

```
