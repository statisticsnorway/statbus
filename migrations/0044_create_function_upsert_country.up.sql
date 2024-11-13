-- Create function for upsert operation on country
\echo admin.upsert_country
CREATE FUNCTION admin.upsert_country()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.country (iso_2, iso_3, iso_num, name, active, custom, updated_at)
    VALUES (NEW.iso_2, NEW.iso_3, NEW.iso_num, NEW.name, true, false, statement_timestamp())
    ON CONFLICT (iso_2, iso_3, iso_num, name)
    DO UPDATE SET
        name = EXCLUDED.name,
        custom = false,
        updated_at = statement_timestamp()
    WHERE country.id = EXCLUDED.id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create function for deleting stale countries
\echo admin.delete_stale_country
CREATE FUNCTION admin.delete_stale_country()
RETURNS TRIGGER AS $$
BEGIN
    DELETE FROM public.country
    WHERE updated_at < statement_timestamp();
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Create a view for country
\echo public.country_view
CREATE VIEW public.country_view
WITH (security_invoker=on) AS
SELECT id, iso_2, iso_3, iso_num, name, active, custom
FROM public.country;

-- Create triggers for the view
CREATE TRIGGER upsert_country_view
INSTEAD OF INSERT ON public.country_view
FOR EACH ROW
EXECUTE FUNCTION admin.upsert_country();

CREATE TRIGGER delete_stale_country_view
AFTER INSERT ON public.country_view
FOR EACH STATEMENT
EXECUTE FUNCTION admin.delete_stale_country();


\copy public.country_view(name, iso_2, iso_3, iso_num) FROM 'dbseed/country/country_codes.csv' WITH (FORMAT csv, DELIMITER ',', QUOTE '"', HEADER true);