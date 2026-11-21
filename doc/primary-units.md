# What a primary unit passes on

An enterprise row (`public.enterprise`) owns only `short_name`, `enabled` and its edit stamps. Every other value an enterprise shows is derived when the timeline is built:

- `legal_unit.primary_for_enterprise` marks the enterprise's **primary legal unit**.
- `establishment.primary_for_enterprise` marks the **primary establishment** of an enterprise that has no legal units (an informal establishment).
- `establishment.primary_for_legal_unit` marks a legal unit's primary establishment. **Nothing in a legal unit comes from that establishment**. The flag only selects which establishment is primary.

Values flow upward only. Editing an enterprise (its `short_name`) never changes a legal unit or an establishment.

## Enterprise fields: where each comes from

| Enterprise field | Comes from |
|---|---|
| name | enterprise `short_name` when set, otherwise the primary legal unit's name, otherwise the primary establishment's name |
| birth date, death date | primary legal unit, otherwise primary establishment |
| primary and secondary activity category | primary legal unit, otherwise primary establishment |
| sector | primary legal unit, otherwise primary establishment |
| legal form | primary legal unit **only** (empty for an enterprise with only an establishment) |
| physical and postal location (address, postcode, postplace, region, country, coordinates), `domestic` | primary legal unit, otherwise primary establishment |
| contact (web, email, phone, landline, mobile, fax) | primary legal unit, otherwise primary establishment |
| unit size, status | primary legal unit, otherwise primary establishment |
| used for counting | primary legal unit, otherwise primary establishment |
| external identifiers | the enterprise's own identifiers if it has any, otherwise the primary establishment's, otherwise the primary legal unit's (the whole set, not field by field) |
| tags | the enterprise's own tags only |
| data sources | union over the primary units **and all** legal units and establishments of the enterprise |
| statistics (`stats_summary`) | aggregate over **all** included (used for counting) legal units and establishments, not only the primary one. The enterprise has no `stats` of its own |
| related/included/excluded legal unit and establishment ids | all legal units and establishments of the enterprise |
| last edit (comment, user, time) | the most recent of the enterprise row, the primary legal unit and the primary establishment |
| enabled | enterprise row |

"Otherwise" is `COALESCE` per column. A mixed result is possible: if the primary legal unit has no phone number but the primary establishment of the enterprise does, the enterprise shows that phone number. In practice an enterprise with a legal unit has no `primary_for_enterprise` establishment.

## Legal unit fields

A legal unit's name, dates, activities, sector, legal form, locations, contact, unit size, status, external identifiers and tags all come from its own rows (`legal_unit`, and `activity`/`location`/`contact`/`stat_for_unit`/`external_ident`/`tag_for_unit` rows with `legal_unit_id` set). Only these are aggregated from its establishments, all of them rather than the primary one:

- `stats_summary`: its own statistics merged with those of its included establishments (only when the legal unit is used for counting).
- `data_source_ids`/`data_source_codes`: union with its establishments' data sources.
- related/included/excluded establishment ids list them.

## Precise sources

- `public.timeline_enterprise_def` (view, see `doc/db/view/public_timeline_enterprise_def.md`): CTE `enterprise_with_primary_and_aggregation`, subquery `basis`. `enplu` is `timeline_legal_unit` filtered on `primary_for_enterprise = true`, `enpes` is `timeline_establishment` filtered on `primary_for_enterprise = true`. Expressions such as `COALESCE(NULLIF(ten.short_name,''), enplu.name, enpes.name) AS name`, `COALESCE(enplu.sector_id, enpes.sector_id)`, and `enplu.legal_form_id` (no establishment fallback). `last_edit` picks the latest `edit_at` from `ten`, `enplu`, `enpes`. CTE `aggregation` merges `stats_summary` (`jsonb_stats_merge_agg ... FILTER (WHERE used_for_counting)`) and unions data sources over all `timeline_legal_unit` and `timeline_establishment` rows with that `enterprise_id`.
- `import.get_statistical_unit_data_partial(statistical_unit_type, int4multirange)`, enterprise branch: `external_idents = COALESCE(eia1, eia2, eia3)` with enterprise, then `primary_establishment_id`, then `primary_legal_unit_id` identifiers. `tag_paths` from `tag_for_unit.enterprise_id`. `stats` is `NULL`.
- `public.timeline_legal_unit_def_for(integer[])` (wrapped by view `public.timeline_legal_unit_def`): every attribute joins on `legal_unit_id = lu.id`. CTE `establishment_aggs` over `timeline_establishment.legal_unit_id` provides only data sources, establishment id lists and `stats_summary`. The final `stats_summary` is `jsonb_stats_merge(esa.stats_summary, basis.stats_summary)` when `used_for_counting`.
