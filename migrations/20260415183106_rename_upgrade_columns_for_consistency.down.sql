-- Reverse the 4 column renames from the up migration.
BEGIN;

ALTER TABLE public.upgrade RENAME COLUMN rolled_back_at TO rollback_completed_at;
ALTER TABLE public.upgrade RENAME COLUMN docker_images_downloaded TO images_downloaded;
ALTER TABLE public.upgrade RENAME COLUMN version TO discover_version_tag;
ALTER TABLE public.upgrade RENAME COLUMN topological_order TO position;

END;
