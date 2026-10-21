-- STATBUS-524: Replace the ten hand-written admin.*_id_exists CHECK constraints with real
-- foreign keys. The CHECKs call STABLE functions, which pg_dump inlines into CREATE TABLE
-- and cannot use to order table data, so a pg_dump -Fc backup failed to restore when the
-- child table sorted before its parent (alphabetical order: external_ident before
-- legal_unit). sql_saga foreign keys are enforced by constraint triggers, which pg_dump
-- writes as post-data objects after all data is loaded, so restore order no longer matters;
-- native foreign keys are likewise restored as post-data ALTER TABLE statements.
--
-- external_ident, tag_for_unit and unit_notes are addenda to a statistical unit.
-- legal_unit/establishment are temporal tables (id is not plain-unique), so the addenda
-- reference them through sql_saga regular foreign keys: the id must exist somewhere in the
-- unit's history, the same guarantee the CHECKs gave. person/power_group are regular
-- tables, so the addenda reference them through native foreign keys. Native references use
-- ON DELETE CASCADE: the addendum goes with its unit. sql_saga 1.3 supports only NO
-- ACTION/RESTRICT for its foreign keys, so the temporal references use NO ACTION: a
-- legal unit or establishment that still has addenda cannot be deleted until they are.
-- Nothing in StatBus deletes those units row by row (reset truncates parents and
-- children together). Cascade for them follows when sql_saga supports it (requested
-- upstream, sql_saga todo.md).
BEGIN;
SET LOCAL lock_timeout = '30s';

-- Replace the legal_unit/establishment CHECKs with sql_saga regular foreign keys.
-- The CHECK is dropped first so the generated constraint trigger takes the clean name
-- <table>_<column>_check. add_foreign_key validates existing rows and aborts the
-- migration with a foreign key error naming any orphan row.
ALTER TABLE public.external_ident DROP CONSTRAINT external_ident_legal_unit_id_check;
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.external_ident',
    fk_column_names => ARRAY['legal_unit_id'],
    pk_table_oid => 'public.legal_unit',
    pk_column_names => ARRAY['id']);

ALTER TABLE public.external_ident DROP CONSTRAINT external_ident_establishment_id_check;
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.external_ident',
    fk_column_names => ARRAY['establishment_id'],
    pk_table_oid => 'public.establishment',
    pk_column_names => ARRAY['id']);

ALTER TABLE public.tag_for_unit DROP CONSTRAINT tag_for_unit_legal_unit_id_check;
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.tag_for_unit',
    fk_column_names => ARRAY['legal_unit_id'],
    pk_table_oid => 'public.legal_unit',
    pk_column_names => ARRAY['id']);

ALTER TABLE public.tag_for_unit DROP CONSTRAINT tag_for_unit_establishment_id_check;
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.tag_for_unit',
    fk_column_names => ARRAY['establishment_id'],
    pk_table_oid => 'public.establishment',
    pk_column_names => ARRAY['id']);

ALTER TABLE public.unit_notes DROP CONSTRAINT unit_notes_legal_unit_id_check;
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.unit_notes',
    fk_column_names => ARRAY['legal_unit_id'],
    pk_table_oid => 'public.legal_unit',
    pk_column_names => ARRAY['id']);

ALTER TABLE public.unit_notes DROP CONSTRAINT unit_notes_establishment_id_check;
SELECT sql_saga.add_foreign_key(
    fk_table_oid => 'public.unit_notes',
    fk_column_names => ARRAY['establishment_id'],
    pk_table_oid => 'public.establishment',
    pk_column_names => ARRAY['id']);

-- Replace the person/power_group CHECKs with native foreign keys.
ALTER TABLE public.external_ident DROP CONSTRAINT external_ident_person_id_check;
ALTER TABLE public.external_ident ADD CONSTRAINT external_ident_person_id_fkey
    FOREIGN KEY (person_id) REFERENCES public.person(id) ON DELETE CASCADE;

ALTER TABLE public.external_ident DROP CONSTRAINT external_ident_power_group_id_check;
ALTER TABLE public.external_ident ADD CONSTRAINT external_ident_power_group_id_fkey
    FOREIGN KEY (power_group_id) REFERENCES public.power_group(id) ON DELETE CASCADE;

ALTER TABLE public.tag_for_unit DROP CONSTRAINT tag_for_unit_power_group_id_check;
ALTER TABLE public.tag_for_unit ADD CONSTRAINT tag_for_unit_power_group_id_fkey
    FOREIGN KEY (power_group_id) REFERENCES public.power_group(id) ON DELETE CASCADE;

ALTER TABLE public.unit_notes DROP CONSTRAINT unit_notes_power_group_id_check;
ALTER TABLE public.unit_notes ADD CONSTRAINT unit_notes_power_group_id_fkey
    FOREIGN KEY (power_group_id) REFERENCES public.power_group(id) ON DELETE CASCADE;

-- Document each new reference at its definition: an addendum reference that belongs to
-- its unit. For sql_saga foreign keys the child-side enforcement object is the
-- <table>_<column>_check constraint trigger.
COMMENT ON TRIGGER external_ident_legal_unit_id_check ON public.external_ident IS
    'Addendum reference: the external identifier belongs to this legal unit (sql_saga regular foreign key).';
COMMENT ON TRIGGER external_ident_establishment_id_check ON public.external_ident IS
    'Addendum reference: the external identifier belongs to this establishment (sql_saga regular foreign key).';
COMMENT ON TRIGGER tag_for_unit_legal_unit_id_check ON public.tag_for_unit IS
    'Addendum reference: the tag belongs to this legal unit (sql_saga regular foreign key).';
COMMENT ON TRIGGER tag_for_unit_establishment_id_check ON public.tag_for_unit IS
    'Addendum reference: the tag belongs to this establishment (sql_saga regular foreign key).';
COMMENT ON TRIGGER unit_notes_legal_unit_id_check ON public.unit_notes IS
    'Addendum reference: the note belongs to this legal unit (sql_saga regular foreign key).';
COMMENT ON TRIGGER unit_notes_establishment_id_check ON public.unit_notes IS
    'Addendum reference: the note belongs to this establishment (sql_saga regular foreign key).';
COMMENT ON CONSTRAINT external_ident_person_id_fkey ON public.external_ident IS
    'Addendum reference that cascades with its unit: the external identifier belongs to this person.';
COMMENT ON CONSTRAINT external_ident_power_group_id_fkey ON public.external_ident IS
    'Addendum reference that cascades with its unit: the external identifier belongs to this power group.';
COMMENT ON CONSTRAINT tag_for_unit_power_group_id_fkey ON public.tag_for_unit IS
    'Addendum reference that cascades with its unit: the tag belongs to this power group.';
COMMENT ON CONSTRAINT unit_notes_power_group_id_fkey ON public.unit_notes IS
    'Addendum reference that cascades with its unit: the note belongs to this power group.';

-- The helpers existed only for the dropped CHECKs.
DROP FUNCTION admin.legal_unit_id_exists(integer);
DROP FUNCTION admin.establishment_id_exists(integer);
DROP FUNCTION admin.person_id_exists(integer);
DROP FUNCTION admin.power_group_id_exists(integer);

END;
