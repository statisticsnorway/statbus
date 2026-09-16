-- Upgrade-arc fixture migration 2 (STATBUS-071 5d / doc-017 §5).
CREATE TABLE public.upgrade_arc_fixture_2 (
    id integer PRIMARY KEY,
    note text NOT NULL
);
INSERT INTO public.upgrade_arc_fixture_2 (id, note) VALUES (1, 'arc2');
