-- Migration 20260415123856: backfill_docker_images_ready_on_completed
--
-- #26b established the invariant: state='completed' implies docker_images_ready=true
-- (a successful upgrade provably ran with the image — if the upgrade finished, the
-- image was present). From #26b onward, executeUpgrade sets docker_images_ready=true
-- at every completion UPDATE. This migration backfills the invariant for historical
-- completed rows that pre-date #26b and still have docker_images_ready=false.
--
-- Idempotent: re-running affects 0 rows once the backfill has run.
BEGIN;

UPDATE public.upgrade
   SET docker_images_ready = true
 WHERE state = 'completed'
   AND docker_images_ready = false;

END;
