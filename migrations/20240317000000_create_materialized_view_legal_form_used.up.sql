BEGIN;

CREATE VIEW public.legal_form_used_def AS
SELECT lf.id
     , lf.code
     , lf.name
FROM public.legal_form AS lf
WHERE lf.id IN (SELECT legal_form_id FROM public.statistical_unit WHERE legal_form_id IS NOT NULL)
  AND lf.active
ORDER BY lf.id;

CREATE UNLOGGED TABLE public.legal_form_used AS
SELECT * FROM public.legal_form_used_def;

CREATE UNIQUE INDEX "legal_form_used_key" ON public.legal_form_used (code);

CREATE FUNCTION public.legal_form_used_derive()
RETURNS void
LANGUAGE plpgsql
AS $legal_form_used_derive$
BEGIN
    RAISE DEBUG 'Running legal_form_used_derive()';
    DELETE FROM public.legal_form_used;
    INSERT INTO public.legal_form_used
    SELECT * FROM public.legal_form_used_def;
END;
$legal_form_used_derive$;

END;
