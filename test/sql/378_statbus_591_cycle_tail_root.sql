-- STATBUS-591: a cycle's terminal tail can have the smallest surrogate LU id.
BEGIN;
\i test/setup.sql
CALL test.set_user_from_email('test.admin@statbus.org');
SET LOCAL datestyle = 'ISO, YMD';
SET LOCAL client_min_messages = warning;

INSERT INTO public.import_job (definition_id, slug, description, edit_comment, review)
SELECT id, 'import_378_rels', 'Cycle tail root regression', 'Test 378', false
FROM public.import_definition WHERE slug = 'legal_relationship_source_dates';
SELECT id AS job_id FROM public.import_job WHERE slug = 'import_378_rels' \gset

INSERT INTO public.legal_rel_type (code, name, primary_influencer_only, enabled, custom)
VALUES ('T378_a', 'Test 378 parent A', true, true, false),
       ('T378_b', 'Test 378 parent B', true, true, false);
INSERT INTO public.enterprise (short_name, edit_by_user_id)
SELECT 'T378_' || n, auth.uid() FROM generate_series(1,12) AS n;
INSERT INTO public.legal_unit (valid_from, name, enterprise_id, primary_for_enterprise, status_id, edit_by_user_id)
SELECT '2020-01-01', 'T378 unit ' || e.short_name, e.id, true,
       (SELECT id FROM public.status WHERE code = 'active'), auth.uid()
FROM public.enterprise AS e WHERE e.short_name LIKE 'T378\_%' ORDER BY e.id;
CREATE TEMP TABLE t378_unit ON COMMIT DROP AS
SELECT id, row_number() OVER (ORDER BY id)::integer AS n
FROM public.legal_unit WHERE name LIKE 'T378 unit %';

-- Component 1: terminal 1 below cycle 2 <-> 3. Component 4: ordinary cycle.
-- Component 7: natural root with two levels. Component 10: two natural roots.
INSERT INTO public.legal_relationship (influencing_id, influenced_id, type_id, valid_from, valid_to, percentage, edit_by_user_id)
SELECT p.id, c.id, t.id, '2020-01-01', '2024-12-31', 100, auth.uid()
FROM (VALUES (2,3,'T378_a'),(3,2,'T378_a'),(2,1,'T378_a'),
             (4,5,'T378_a'),(5,6,'T378_a'),(6,4,'T378_a'),
             (7,8,'T378_a'),(8,9,'T378_a'),
             (10,12,'T378_a'),(11,12,'T378_b')) AS edge(parent,child,type)
JOIN t378_unit AS p ON p.n = edge.parent
JOIN t378_unit AS c ON c.n = edge.child
JOIN public.legal_rel_type AS t ON t.code = edge.type;

CALL import.process_power_group_link(p_job_id => :job_id, p_batch_seq => NULL, p_step_code => 'power_group_link');

-- Exact edge membership and influenced levels, expressed in surrogate order.
SELECT p.n AS parent, c.n AS child, min(member.n) AS component,
       lr.derived_influenced_power_level AS level
FROM public.legal_relationship AS lr
JOIN t378_unit AS p ON p.id = lr.influencing_id
JOIN t378_unit AS c ON c.id = lr.influenced_id
JOIN public.legal_relationship AS peer ON peer.derived_power_group_id = lr.derived_power_group_id
JOIN t378_unit AS member ON member.id IN (peer.influencing_id, peer.influenced_id)
GROUP BY p.n, c.n, lr.derived_influenced_power_level ORDER BY p.n, c.n;

-- Natural roots remain visible at level zero, including both multi roots.
SELECT u.n AS natural_root, membership.power_level, membership.valid_range
FROM public.power_group_membership AS membership
JOIN t378_unit AS u ON u.id = membership.legal_unit_id
WHERE membership.power_level = 0 ORDER BY u.n;

-- Cycles retain smallest eligible surrogate, multi retains smallest natural root.
SELECT u.n AS derived_root, pr.derived_root_status, pr.valid_from, pr.valid_to,
       EXISTS (SELECT FROM public.legal_relationship AS lr
               WHERE lr.derived_power_group_id = pr.power_group_id
                 AND lr.influencing_id = pr.derived_root_legal_unit_id
                 AND lr.valid_range && pr.valid_range) AS valid_influencing_root
FROM public.power_root AS pr JOIN t378_unit AS u ON u.id = pr.derived_root_legal_unit_id
ORDER BY u.n;

UPDATE public.power_root AS pr SET custom_root_legal_unit_id = custom.id
FROM t378_unit AS derived JOIN t378_unit AS custom ON custom.n = derived.n + 1
WHERE pr.derived_root_legal_unit_id = derived.id AND derived.n IN (2,4,10);
CREATE TEMP TABLE t378_first ON COMMIT DROP AS
SELECT id, derived_power_group_id, derived_influenced_power_level FROM public.legal_relationship;
CALL import.process_power_group_link(p_job_id => :job_id, p_batch_seq => NULL, p_step_code => 'power_group_link');
SELECT u.n AS derived_root, custom.n AS custom_root, effective.n AS effective_root,
       pr.derived_root_status, pr.valid_from, pr.valid_to
FROM public.power_root AS pr
JOIN t378_unit AS u ON u.id = pr.derived_root_legal_unit_id
JOIN t378_unit AS custom ON custom.id = pr.custom_root_legal_unit_id
JOIN t378_unit AS effective ON effective.id = pr.root_legal_unit_id
ORDER BY u.n;
SELECT count(*) AS relationships, count(*) FILTER (
    WHERE lr.derived_power_group_id = first.derived_power_group_id
      AND lr.derived_influenced_power_level IS NOT DISTINCT FROM first.derived_influenced_power_level
) AS same_group_and_level
FROM public.legal_relationship AS lr JOIN t378_first AS first USING (id);
ROLLBACK;
