-- Migration 20261119154414: unit photos are small and removed when nothing shows them
-- (w79490). A photo lets a field worker recognise a unit on the next visit; few are
-- expected, so a small size limit keeps the database from filling up, and the
-- database itself deletes a photo once no period of any unit refers to it.
BEGIN;

-- A cropped 512 px JPEG is well under this; the app crops and scales before upload.
ALTER TABLE public.image DROP CONSTRAINT image_size_limit;
ALTER TABLE public.image ADD CONSTRAINT image_size_limit CHECK (length(data) <= 262144);

COMMENT ON TABLE public.image IS
  'A unit''s photo (legal_unit.image_id, establishment.image_id), for example a shop front a field worker took to recognise the unit on the next visit. Each period of a unit may refer to a photo. A photo that no row of either table refers to any more is deleted at commit (admin.image_released). Validates magic bytes on insert to prevent XSS attacks via malicious file uploads.';
COMMENT ON COLUMN public.image.data IS
  'Binary image data with EXTERNAL storage (no compression). At most 256 KB (image_size_limit): photos are few and small, cropped to a square and scaled by the app. Validated on insert: only PNG, JPEG, GIF, WebP allowed.';

CREATE TABLE admin.image_released (image_id integer NOT NULL);
COMMENT ON TABLE admin.image_released IS
  'Photos a legal_unit or establishment row stopped referring to in the current transaction, noted by public.image_note_released. A deferred trigger on this table (public.image_drop_released) deletes each at commit when no row refers to it any more, and removes the note; the table is empty outside a transaction. The deferred work sits here rather than on legal_unit and establishment because deferred events pending on those tables would make ALTER TABLE on them fail inside the transaction, and imports enable and disable sql_saga''s triggers between batches. No grants: only the SECURITY DEFINER trigger functions use it.';

CREATE FUNCTION public.image_note_released() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, admin, pg_temp AS $image_note_released$
BEGIN
  INSERT INTO admin.image_released (image_id) VALUES (OLD.image_id);
  RETURN NULL;
END;
$image_note_released$;
COMMENT ON FUNCTION public.image_note_released() IS
  'Notes, in admin.image_released, the photo a legal_unit or establishment row stopped referring to, so it is checked at commit. SECURITY DEFINER because admin.image_released has no grants for the editing roles.';

CREATE FUNCTION public.image_drop_released() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, admin, pg_temp AS $image_drop_released$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.legal_unit AS lu WHERE lu.image_id = NEW.image_id)
     AND NOT EXISTS (SELECT 1 FROM public.establishment AS es WHERE es.image_id = NEW.image_id) THEN
    DELETE FROM public.image AS i WHERE i.id = NEW.image_id;
  END IF;
  DELETE FROM admin.image_released AS r WHERE r.image_id = NEW.image_id;
  RETURN NULL;
END;
$image_drop_released$;
COMMENT ON FUNCTION public.image_drop_released() IS
  'At commit, deletes a released photo when no legal_unit or establishment row refers to it, and clears its note. Running at commit means it sees the transaction''s final rows: sql_saga splits and rewrites a unit''s periods within one statement, and a photo still shown by any period stays. SECURITY DEFINER so the cleanup does not depend on the editing user''s rights; it only ever deletes an unreferenced photo.';

CREATE TRIGGER legal_unit_image_released
  AFTER UPDATE OF image_id OR DELETE ON public.legal_unit
  FOR EACH ROW WHEN (OLD.image_id IS NOT NULL)
  EXECUTE FUNCTION public.image_note_released();

CREATE TRIGGER establishment_image_released
  AFTER UPDATE OF image_id OR DELETE ON public.establishment
  FOR EACH ROW WHEN (OLD.image_id IS NOT NULL)
  EXECUTE FUNCTION public.image_note_released();

CREATE CONSTRAINT TRIGGER image_released_check
  AFTER INSERT ON admin.image_released
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public.image_drop_released();

-- Photos left behind before the cleanup existed: removed now.
DELETE FROM public.image AS i
WHERE NOT EXISTS (SELECT 1 FROM public.legal_unit AS lu WHERE lu.image_id = i.id)
  AND NOT EXISTS (SELECT 1 FROM public.establishment AS es WHERE es.image_id = i.id);

END;
