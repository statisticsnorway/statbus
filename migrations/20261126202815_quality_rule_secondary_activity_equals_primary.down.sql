-- Down Migration 20261126202815: PostgreSQL cannot drop an enum value, so
-- 'secondary_activity_equals_primary' stays; 20261126202816's down migration removes every use of it.
BEGIN;

COMMENT ON TYPE public.quality_rule IS
  'The kinds of data-quality check (05pe0x). missing_region: a legal unit or establishment located in the installation''s own country (settings.country_id) without a region (pkne34). missing_activity_category: a legal unit or establishment without a primary activity category. missing_physical_location: a legal unit or establishment without a physical location. establishment_activity_differs: a legal unit whose primary establishment has another primary activity category (xz3jej). establishments_above_legal_unit: a legal unit whose counted establishments'' values of a summed variable add up to more than its own value (ca6dk5). legal_unit_above_establishments: a legal unit whose own value of a summed variable is above its counted establishments'' sum while every one of them has a value (ca6dk5). The last two are a check per summed variable (public.quality_rule_per_stat). A new rule is a new value here with its rule in public.quality_finding_def; the app''s wording is keyed by this enum, so the type check fails until the rule has a name.';

END;
