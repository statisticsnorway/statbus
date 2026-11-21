SELECT t, u.email, n FROM (
 SELECT 'enterprise' t, edit_by_user_id, count(*) n FROM public.enterprise GROUP BY 2 UNION ALL
 SELECT 'legal_unit', edit_by_user_id, count(*) FROM public.legal_unit GROUP BY 2 UNION ALL
 SELECT 'establishment', edit_by_user_id, count(*) FROM public.establishment GROUP BY 2 UNION ALL
 SELECT 'external_ident', edit_by_user_id, count(*) FROM public.external_ident GROUP BY 2 UNION ALL
 SELECT 'location', edit_by_user_id, count(*) FROM public.location GROUP BY 2 UNION ALL
 SELECT 'activity', edit_by_user_id, count(*) FROM public.activity GROUP BY 2 UNION ALL
 SELECT 'contact', edit_by_user_id, count(*) FROM public.contact GROUP BY 2 UNION ALL
 SELECT 'stat_for_unit', edit_by_user_id, count(*) FROM public.stat_for_unit GROUP BY 2 UNION ALL
 SELECT 'legal_relationship', edit_by_user_id, count(*) FROM public.legal_relationship GROUP BY 2 UNION ALL
 SELECT 'tag_for_unit', edit_by_user_id, count(*) FROM public.tag_for_unit GROUP BY 2
) s LEFT JOIN auth.user u ON u.id = s.edit_by_user_id ORDER BY 1,2;
SELECT errors FROM public.es_sel_data WHERE state='error' LIMIT 3;
