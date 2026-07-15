-- Upgrade-arc healthpark fixture V1 / V_marker (STATBUS-145 doc-029).
-- Benign, always succeeds — proves the delta genuinely applied before
-- V2 (below) breaks health past warmup.
CREATE TABLE public.upgrade_arc_healthpark_fixture (
    id integer PRIMARY KEY,
    note text NOT NULL
);
INSERT INTO public.upgrade_arc_healthpark_fixture (id, note) VALUES (1, 'healthpark');
