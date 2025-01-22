BEGIN;

CREATE MATERIALIZED VIEW public.legal_form_used AS
SELECT lf.id
     , lf.code
     , lf.name
FROM public.legal_form AS lf
WHERE lf.id IN (SELECT legal_form_id FROM public.statistical_unit WHERE legal_form_id IS NOT NULL)
  AND lf.active
ORDER BY lf.id;

CREATE UNIQUE INDEX "legal_form_used_key"
    ON public.legal_form_used (code);

END;