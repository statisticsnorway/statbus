```sql
                                                                                     Table "public.quality_check_switched_on"
       Column       |     Type     | Collation | Nullable | Default | Storage | Compression | Stats target |                                              Description                                              
--------------------+--------------+-----------+----------+---------+---------+-------------+--------------+-------------------------------------------------------------------------------------------------------
 rule               | quality_rule |           | not null |         | plain   |             |              | 
 stat_definition_id | integer      |           |          |         | plain   |             |              | The summed variable of a per-variable rule (public.quality_rule_per_stat); NULL for every other rule.
Indexes:
    "quality_check_switched_on_key" UNIQUE CONSTRAINT, btree (rule, stat_definition_id) NULLS NOT DISTINCT
Check constraints:
    "quality_check_switched_on_variable_matches_rule" CHECK (quality_rule_per_stat(rule) = (stat_definition_id IS NOT NULL))
Foreign-key constraints:
    "quality_check_switched_on_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE CASCADE
Policies:
    POLICY "quality_check_switched_on_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "quality_check_switched_on_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "quality_check_switched_on_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "quality_check_switched_on_rule_not_null" NOT NULL "rule"
Access method: heap

```

**Comment:** The checks an installation has switched on (1tx1ed): shown in the dashboard's Data quality section and the search's Quality filter. Only switched-on checks are stored, so every check, a new variable's checks too, starts off; a fresh installation and reset's customisation scope hold the starting set (public.quality_check_starting_set). A disabled variable keeps its row for when it is enabled again; deleting the variable deletes it. Written by admins on Admin > Data quality checks.
