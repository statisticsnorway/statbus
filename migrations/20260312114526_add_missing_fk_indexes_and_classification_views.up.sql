BEGIN;

-- Part 1: Add missing FK indexes

CREATE INDEX ix_establishment_image_id ON public.establishment(image_id);
CREATE INDEX ix_legal_unit_image_id ON public.legal_unit(image_id);
CREATE INDEX ix_image_uploaded_by_user_id ON public.image(uploaded_by_user_id);
CREATE INDEX ix_tag_parent_id ON public.tag(parent_id);
CREATE INDEX ix_location_region_version_id ON public.location(region_version_id);
CREATE INDEX ix_stat_for_unit_edit_by_user_id ON public.stat_for_unit(edit_by_user_id);
CREATE INDEX ix_power_root_edit_by_user_id ON public.power_root(edit_by_user_id);

-- Part 2: Add missing classification views

-- activity_category_standard: always system-provided (no custom column by design).
CREATE VIEW public.activity_category_standard_ordered WITH (security_invoker=on) AS
SELECT id, code, name, description, code_pattern, enabled, lasts_to
  FROM public.activity_category_standard
 ORDER BY code;

CREATE VIEW public.activity_category_standard_enabled WITH (security_invoker=on) AS
SELECT id, code, name, description, code_pattern, enabled, lasts_to
  FROM public.activity_category_standard_ordered
 WHERE enabled;

-- country: uses iso_2 instead of code for ordering.
CREATE VIEW public.country_ordered WITH (security_invoker=on) AS
SELECT id, iso_2, iso_3, iso_num, name, enabled, custom, created_at, updated_at
  FROM public.country
 ORDER BY iso_2;

CREATE VIEW public.country_enabled WITH (security_invoker=on) AS
SELECT id, iso_2, iso_3, iso_num, name, enabled, custom, created_at, updated_at
  FROM public.country_ordered
 WHERE enabled;

-- region_version and tag: fit the batch API pattern, use generator.
SELECT admin.generate_table_views_for_batch_api('public.region_version');
SELECT admin.generate_table_views_for_batch_api('public.tag');

-- Part 2b: Grant permissions on new views

SELECT admin.grant_permissions_on_views();
SELECT admin.grant_select_on_all_views();

-- Part 3: Document orphaned sequences

COMMENT ON SEQUENCE public.worker_task_priority_seq IS 'Used by worker.process_tasks and derive pipeline procedures to assign monotonically increasing priority values to child tasks.';
COMMENT ON SEQUENCE public.import_job_priority_seq IS 'Used by import_job state change trigger to assign processing priority when jobs enter ready state.';
COMMENT ON SEQUENCE public.power_group_ident_seq IS 'Used to generate unique identifiers for power groups during derive pipeline execution.';

END;
