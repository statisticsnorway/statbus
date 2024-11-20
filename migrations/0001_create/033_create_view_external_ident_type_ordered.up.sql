CREATE VIEW public.external_ident_type_ordered AS
    SELECT *
    FROM public.external_ident_type
    ORDER BY priority ASC NULLS LAST, code
;

CREATE VIEW public.external_ident_type_active AS
    SELECT *
    FROM public.external_ident_type_ordered
    WHERE NOT archived
;