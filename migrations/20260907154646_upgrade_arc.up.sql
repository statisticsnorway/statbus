-- Upgrade-arc fixture migration 1 (STATBUS-071). Observable + reversible;
-- the arc asserts public.upgrade_arc_fixture exists with its row.
CREATE TABLE public.upgrade_arc_fixture (
    id integer PRIMARY KEY,
    note text NOT NULL
);
INSERT INTO public.upgrade_arc_fixture (id, note) VALUES (1, 'arc');
