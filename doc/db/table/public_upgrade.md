```sql
                                           Table "public.upgrade"
          Column          |           Type           | Collation | Nullable |            Default            
--------------------------+--------------------------+-----------+----------+-------------------------------
 id                       | integer                  |           | not null | generated always as identity
 commit_sha               | text                     |           | not null | 
 committed_at             | timestamp with time zone |           | not null | 
 topological_order        | integer                  |           |          | 
 tags                     | text[]                   |           | not null | '{}'::text[]
 release_status           | release_status_type      |           | not null | 'commit'::release_status_type
 summary                  | text                     |           | not null | 
 changes                  | text                     |           |          | 
 release_url              | text                     |           |          | 
 has_migrations           | boolean                  |           | not null | false
 discovered_at            | timestamp with time zone |           | not null | clock_timestamp()
 scheduled_at             | timestamp with time zone |           |          | 
 started_at               | timestamp with time zone |           |          | 
 completed_at             | timestamp with time zone |           |          | 
 error                    | text                     |           |          | 
 rolled_back_at           | timestamp with time zone |           |          | 
 skipped_at               | timestamp with time zone |           |          | 
 from_version             | text                     |           |          | 
 docker_images_downloaded | boolean                  |           | not null | false
 backup_path              | text                     |           |          | 
 superseded_at            | timestamp with time zone |           |          | 
 progress_log             | text                     |           |          | 
 docker_images_ready      | boolean                  |           | not null | false
 release_builds_ready     | boolean                  |           | not null | false
 dismissed_at             | timestamp with time zone |           |          | 
 state                    | upgrade_state            |           | not null | 'available'::upgrade_state
 version                  | text                     |           |          | 
 log_relative_file_path   | text                     |           |          | 
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
Triggers:
    upgrade_notify_daemon_trigger AFTER UPDATE ON upgrade FOR EACH ROW EXECUTE FUNCTION upgrade_notify_daemon()
    upgrade_notify_frontend_trigger AFTER INSERT OR DELETE OR UPDATE ON upgrade FOR EACH ROW EXECUTE FUNCTION upgrade_notify_frontend()

```
