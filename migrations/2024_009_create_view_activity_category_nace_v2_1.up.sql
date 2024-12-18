BEGIN;

\echo public.activity_category_nace_v2_1
CREATE VIEW public.activity_category_nace_v2_1
WITH (security_invoker=on) AS
SELECT acs.code AS standard
     , ac.path
     , ac.label
     , ac.code
     , ac.name
     , ac.description
FROM public.activity_category AS ac
JOIN public.activity_category_standard AS acs
ON ac.standard_id = acs.id
WHERE acs.code = 'nace_v2.1'
ORDER BY path;

CREATE TRIGGER upsert_activity_category_nace_v2_1
INSTEAD OF INSERT ON public.activity_category_nace_v2_1
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_activity_category('nace_v2.1');

CREATE TRIGGER delete_stale_activity_category_nace_v2_1
AFTER INSERT ON public.activity_category_nace_v2_1
FOR EACH STATEMENT
EXECUTE FUNCTION admin.delete_stale_activity_category();

\copy public.activity_category_nace_v2_1(path, name, description) FROM 'dbseed/activity-category-standards/NACE2.1_Structure_Label_Notes_EN.import.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"');

END;