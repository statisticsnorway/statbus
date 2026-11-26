-- Migration 20261126202815: quality rule secondary activity equals primary (qjy2eg)
--
-- Own migration because a new enum value cannot be used in the transaction that adds it;
-- 20261126202816 gives the rule its branch in public.quality_finding_def.
BEGIN;

ALTER TYPE public.quality_rule ADD VALUE IF NOT EXISTS 'secondary_activity_equals_primary';

COMMENT ON TYPE public.quality_rule IS
  'The kinds of data-quality check (05pe0x). missing_region: a legal unit or establishment located in the installation''s own country (settings.country_id) without a region (pkne34). missing_activity_category: a legal unit or establishment without a primary activity category. missing_physical_location: a legal unit or establishment without a physical location. establishment_activity_differs: a legal unit whose primary establishment has another primary activity category (xz3jej). establishments_above_legal_unit: a legal unit whose counted establishments'' values of a summed variable add up to more than its own value (ca6dk5). legal_unit_above_establishments: a legal unit whose own value of a summed variable is above its counted establishments'' sum while every one of them has a value (ca6dk5). secondary_activity_equals_primary: a legal unit or establishment whose secondary activity category is its primary one over the same period, so the secondary activity says nothing (qjy2eg). The per-variable rules are a check per summed variable (public.quality_rule_per_stat). A new rule is a new value here with its rule in public.quality_finding_def; the app''s wording is keyed by this enum, so the type check fails until the rule has a name.';

END;
