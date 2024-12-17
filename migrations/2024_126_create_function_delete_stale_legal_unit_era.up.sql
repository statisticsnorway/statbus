BEGIN;

---- Create function for deleting stale countries
--CREATE FUNCTION admin.delete_stale_legal_unit_era()
--RETURNS TRIGGER AS $$
--BEGIN
--    DELETE FROM public.region
--    WHERE updated_at < statement_timestamp() AND active = false;
--    RETURN NULL;
--END;
--$$ LANGUAGE plpgsql;

--CREATE TRIGGER delete_stale_legal_unit_era
--AFTER INSERT ON public.legal_unit_era
--FOR EACH STATEMENT
--EXECUTE FUNCTION admin.delete_stale_legal_unit_era();

END;
