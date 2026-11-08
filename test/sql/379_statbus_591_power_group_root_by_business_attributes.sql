-- STATBUS-591: the automatic root of a multi-root or cyclic power group is chosen
-- by business attributes, ranked once at the group's start, not by surrogate id.
-- Every case inserts the candidate that must NOT win first, so an id-based rule fails.
BEGIN;
\i test/setup.sql
CALL test.set_user_from_email('test.admin@statbus.org');
SET LOCAL datestyle = 'ISO, YMD';
SET LOCAL client_min_messages = warning;

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_379_rels', 'Deterministic power group root', 'Test 379', false
FROM public.import_definition WHERE slug = 'legal_relationship_source_dates';
SELECT id AS job_id FROM public.import_job WHERE slug = 'import_379_rels' \gset

INSERT INTO public.legal_rel_type (code, name, primary_influencer_only, enabled, custom)
VALUES ('T379_a', 'Test 379 parent A', true, true, false),
       ('T379_b', 'Test 379 parent B', true, true, false);

-- Units in insertion order. key is the test's own label, name and ident are business data.
CREATE TEMP TABLE t379_spec (n integer, key text, name text, ident text) ON COMMIT DROP;
INSERT INTO t379_spec VALUES
    -- Case employees: M1 (5) inserted before M2 (10); M2 must win.
    (1, 'M1', 'Employees small', '379000001'), (2, 'M2', 'Employees large', '379000002'),
    (3, 'M3', 'Employees child', '379000003'),
    -- Case name: no employees, Beta inserted before Alfa; Alfa must win.
    (4, 'N1', 'Beta', '379000004'), (5, 'N2', 'Alfa', '379000005'), (6, 'N3', 'Name child', '379000006'),
    -- Case ident: same name, no employees, 900 inserted before 100; 100 must win.
    (7, 'I1', 'Same name', '379000900'), (8, 'I2', 'Same name', '379000100'), (9, 'I3', 'Ident child', '379000009'),
    -- Case cycle: C1 (1) inserted first, C2 (7), C3 (3); C2 must win.
    (10, 'C1', 'Cycle one', '379000010'), (11, 'C2', 'Cycle two', '379000011'), (12, 'C3', 'Cycle three', '379000012'),
    -- Case once: O1 has 10 at the start and 1 later, O2 always 5. O1 must stay root in both periods.
    (13, 'O2', 'Once steady', '379000013'), (14, 'O1', 'Once falling', '379000014'),
    (15, 'O3', 'Once child', '379000015'), (16, 'O4', 'Once child late', '379000016'),
    -- Case fallback: P1 ranks first but only controls until 2021. P2 takes over in 2022.
    (17, 'P2', 'Fallback second', '379000017'), (18, 'P1', 'Fallback first', '379000018'),
    (19, 'P3', 'Fallback child', '379000019'), (20, 'P4', 'Fallback child late', '379000020'),
    -- Case late join: L2 has more employees but joins in 2022. L1 remains root.
    (21, 'L2', 'Late large', '379000021'), (22, 'L1', 'Late incumbent', '379000022'),
    (23, 'L3', 'Late child', '379000023'),
    -- Case return: Q1 leaves after 2021 and returns in 2024. Q2 retains the choice made in 2022.
    (24, 'Q2', 'Return second', '379000024'), (25, 'Q1', 'Return first', '379000025'),
    (26, 'Q3', 'Return child', '379000026');

INSERT INTO public.enterprise (short_name, edit_by_user_id)
SELECT 'T379_' || s.n, auth.uid() FROM t379_spec AS s ORDER BY s.n;
INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id)
SELECT '2020-01-01', s.name, e.id, true, (SELECT id FROM public.status WHERE code = 'active'), auth.uid()
FROM t379_spec AS s JOIN public.enterprise AS e ON e.short_name = 'T379_' || s.n ORDER BY s.n;
CREATE TEMP TABLE t379_unit ON COMMIT DROP AS
SELECT lu.id, s.key FROM t379_spec AS s
JOIN public.enterprise AS e ON e.short_name = 'T379_' || s.n
JOIN public.legal_unit AS lu ON lu.enterprise_id = e.id;

INSERT INTO public.external_ident (type_id, shape, ident, legal_unit_id, edit_by_user_id)
SELECT t.id, 'regular', s.ident, u.id, auth.uid()
FROM t379_spec AS s JOIN t379_unit AS u USING (key)
JOIN public.external_ident_type AS t ON t.code = 'tax_ident';

INSERT INTO public.stat_for_unit (stat_definition_id, legal_unit_id, valid_from, valid_to, value_int, edit_by_user_id)
SELECT d.id, u.id, v.valid_from::date, v.valid_to::date, v.employees, auth.uid()
FROM (VALUES ('M1', '2020-01-01', 'infinity', 5), ('M2', '2020-01-01', 'infinity', 10),
             ('C1', '2020-01-01', 'infinity', 1), ('C2', '2020-01-01', 'infinity', 7),
             ('C3', '2020-01-01', 'infinity', 3),
             ('O1', '2020-01-01', '2021-12-31', 10),
             ('O2', '2020-01-01', 'infinity', 5),
             ('P1', '2020-01-01', 'infinity', 10), ('P2', '2020-01-01', 'infinity', 5),
             ('L1', '2020-01-01', 'infinity', 5), ('L2', '2020-01-01', 'infinity', 20),
             ('Q1', '2020-01-01', 'infinity', 10), ('Q2', '2020-01-01', 'infinity', 5))
     AS v(key, valid_from, valid_to, employees)
JOIN t379_unit AS u USING (key)
JOIN public.stat_definition AS d ON d.code = 'employees';
-- O1's later period is a new version of the same temporal row, so it reuses that row's id.
INSERT INTO public.stat_for_unit (id, stat_definition_id, legal_unit_id, valid_from, valid_to, value_int, edit_by_user_id)
SELECT s.id, s.stat_definition_id, s.legal_unit_id, '2022-01-01', 'infinity', 1, auth.uid()
FROM public.stat_for_unit AS s JOIN t379_unit AS u ON u.id = s.legal_unit_id AND u.key = 'O1';

INSERT INTO public.legal_relationship (influencing_id, influenced_id, type_id, valid_from, valid_to, percentage, edit_by_user_id)
SELECT p.id, c.id, t.id, edge.valid_from::date, edge.valid_to::date, 100, auth.uid()
FROM (VALUES ('M1','M3','T379_a','2020-01-01','2024-12-31'), ('M2','M3','T379_b','2020-01-01','2024-12-31'),
             ('N1','N3','T379_a','2020-01-01','2024-12-31'), ('N2','N3','T379_b','2020-01-01','2024-12-31'),
             ('I1','I3','T379_a','2020-01-01','2024-12-31'), ('I2','I3','T379_b','2020-01-01','2024-12-31'),
             ('C1','C2','T379_a','2020-01-01','2024-12-31'), ('C2','C3','T379_a','2020-01-01','2024-12-31'),
             ('C3','C1','T379_a','2020-01-01','2024-12-31'),
             ('O1','O3','T379_a','2020-01-01','2021-12-31'), ('O2','O3','T379_b','2020-01-01','2021-12-31'),
             ('O1','O4','T379_a','2022-01-01','2024-12-31'), ('O2','O4','T379_b','2022-01-01','2024-12-31'),
             ('P1','P3','T379_a','2020-01-01','2021-12-31'), ('P2','P3','T379_b','2020-01-01','2024-12-31'),
             ('P2','P4','T379_b','2022-01-01','2024-12-31'),
             ('L1','L3','T379_a','2020-01-01','2024-12-31'), ('L2','L3','T379_b','2022-01-01','2024-12-31'),
             ('Q1','Q3','T379_a','2020-01-01','2021-12-31'),
             ('Q2','Q3','T379_b','2020-01-01','2024-12-31'))
     AS edge(parent, child, type, valid_from, valid_to)
JOIN t379_unit AS p ON p.key = edge.parent
JOIN t379_unit AS c ON c.key = edge.child
JOIN public.legal_rel_type AS t ON t.code = edge.type;
-- The returning relationship is another era of the same temporal identity.
INSERT INTO public.legal_relationship (id, influencing_id, influenced_id, type_id,
    valid_from, valid_to, percentage, edit_by_user_id)
SELECT lr.id, lr.influencing_id, lr.influenced_id, lr.type_id,
       '2024-01-01', '2024-12-31', lr.percentage, auth.uid()
FROM public.legal_relationship AS lr
JOIN t379_unit AS parent ON parent.id = lr.influencing_id AND parent.key = 'Q1';

CALL import.process_power_group_link(p_job_id => :job_id, p_batch_seq => NULL, p_step_code => 'power_group_link');

-- The automatic root per group and period, named by the test's labels.
-- Expected: M2, N2 (Alfa), I2 (ident 100), C2, O1 throughout, P1 then P2,
-- L1 despite L2 joining, Q1 until departure then Q2 even after Q1 returns.
SELECT string_agg(DISTINCT member.key, ',' ORDER BY member.key) AS group_members,
       root.key AS derived_root, pr.derived_root_status, pr.valid_from, pr.valid_to
FROM public.power_root AS pr
JOIN t379_unit AS root ON root.id = pr.derived_root_legal_unit_id
JOIN public.legal_relationship AS lr ON lr.derived_power_group_id = pr.power_group_id
JOIN t379_unit AS member ON member.id IN (lr.influencing_id, lr.influenced_id)
GROUP BY pr.id, root.key, pr.derived_root_status, pr.valid_from, pr.valid_to
ORDER BY group_members, pr.valid_from;

-- A custom root override survives reprocessing and the derived choice is unchanged.
CREATE TEMP TABLE t379_first ON COMMIT DROP AS
SELECT power_group_id, valid_range, derived_root_legal_unit_id FROM public.power_root;
UPDATE public.power_root AS pr SET custom_root_legal_unit_id = custom.id
FROM t379_unit AS derived, t379_unit AS custom
WHERE pr.derived_root_legal_unit_id = derived.id AND derived.key = 'M2' AND custom.key = 'M1';
CALL import.process_power_group_link(p_job_id => :job_id, p_batch_seq => NULL, p_step_code => 'power_group_link');
SELECT derived.key AS derived_root, custom.key AS custom_root, effective.key AS effective_root
FROM public.power_root AS pr
JOIN t379_unit AS derived ON derived.id = pr.derived_root_legal_unit_id
JOIN t379_unit AS custom ON custom.id = pr.custom_root_legal_unit_id
JOIN t379_unit AS effective ON effective.id = pr.root_legal_unit_id;
SELECT count(*) AS root_rows, count(*) FILTER (
    WHERE pr.derived_root_legal_unit_id = first.derived_root_legal_unit_id) AS same_derived_root
FROM public.power_root AS pr
JOIN t379_first AS first ON first.power_group_id = pr.power_group_id AND first.valid_range = pr.valid_range;
ROLLBACK;
