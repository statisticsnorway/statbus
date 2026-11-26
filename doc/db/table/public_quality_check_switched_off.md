```sql
                                                                                     Table "public.quality_check_switched_off"
       Column       |     Type     | Collation | Nullable | Default | Storage | Compression | Stats target |                                              Description                                              
--------------------+--------------+-----------+----------+---------+---------+-------------+--------------+-------------------------------------------------------------------------------------------------------
 rule               | quality_rule |           | not null |         | plain   |             |              | 
 stat_definition_id | integer      |           |          |         | plain   |             |              | The summed variable of a per-variable rule (public.quality_rule_per_stat); NULL for every other rule.
Indexes:
    "quality_check_switched_off_key" UNIQUE CONSTRAINT, btree (rule, stat_definition_id) NULLS NOT DISTINCT
Check constraints:
    "quality_check_switched_off_variable_matches_rule" CHECK (quality_rule_per_stat(rule) = (stat_definition_id IS NOT NULL))
Foreign-key constraints:
    "quality_check_switched_off_stat_definition_id_fkey" FOREIGN KEY (stat_definition_id) REFERENCES stat_definition(id) ON DELETE CASCADE
Policies:
    POLICY "quality_check_switched_off_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "quality_check_switched_off_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "quality_check_switched_off_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "quality_check_switched_off_rule_not_null" NOT NULL "rule"
Access method: heap

```

**Comment:** The checks an installation has switched off (05pe0x): hidden from the dashboard's Data quality section and the search's Quality filter. Only switched-off checks are stored, so every check, a new variable's checks too, starts on. A disabled variable keeps its row for when it is enabled again; deleting the variable deletes it. Written by admins on Admin > Data quality checks; reset's customisation scope empties it.
