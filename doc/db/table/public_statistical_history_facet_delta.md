```sql
                                                                                                                                                                                                                                                          Table "public.statistical_history_facet_delta"
                  Column                  |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target |                                                                                                                                                                                                     Description                                                                                                                                                                                                      
------------------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 unit_type                                | statistical_unit_type |           | not null |         | plain    |             |              | 
 primary_activity_category_path           | ltree                 |           |          |         | extended |             |              | 
 secondary_activity_category_path         | ltree                 |           |          |         | extended |             |              | 
 sector_path                              | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                            | integer               |           |          |         | plain    |             |              | 
 physical_region_path                     | ltree                 |           |          |         | extended |             |              | 
 physical_country_id                      | integer               |           |          |         | plain    |             |              | 
 unit_size_id                             | integer               |           |          |         | plain    |             |              | 
 status_id                                | integer               |           |          |         | plain    |             |              | 
 on_month                                 | date                  |           | not null |         | plain    |             |              | First day of the month in which the change takes effect. Every report period ends on a month end, and a change on any day of a month is in the stock at that month's end, so bucketing by month gives the same stock at every period end as the exact dates. It keeps one row per cell and month however many changes fall inside the month, and changes of a unit that undo each other within a month leave no row.
 exists_added_count                       | integer               |           | not null |         | plain    |             |              | Units that start to exist in this cell: their existence (public.unit_existence_from/until, STATBUS-460) begins without continuing an earlier one.
 exists_removed_count                     | integer               |           | not null |         | plain    |             |              | Units that stop existing in this cell: their existence ends without a following one.
 countable_added_count                    | integer               |           | not null |         | plain    |             |              | Units that start to be counted (used_for_counting) in this cell without having been counted just before.
 countable_removed_count                  | integer               |           | not null |         | plain    |             |              | Units that stop being counted in this cell without being counted just after.
 exists_moved_in_count                    | integer               |           | not null |         | plain    |             |              | Units that continue to exist and enter this cell from another (any facet dimension changed). A move counts on both sides, so the stock of every cell follows it.
 exists_moved_out_count                   | integer               |           | not null |         | plain    |             |              | Units that continue to exist and leave this cell for another.
 countable_moved_in_count                 | integer               |           | not null |         | plain    |             |              | Counted units that stay counted and enter this cell from another.
 countable_moved_out_count                | integer               |           | not null |         | plain    |             |              | Counted units that stay counted and leave this cell for another.
 births                                   | integer               |           | not null |         | plain    |             |              | Counted units whose existence starts at their birth_date in this month: born here, as the data records it. A unit whose first version starts after its birth_date enters as exists_added_count only (STATBUS-580 flags such imports).
 deaths                                   | integer               |           | not null |         | plain    |             |              | Counted units whose existence ends at their death_date in this month.
 name_change_count                        | integer               |           | not null |         | plain    |             |              | Counted versions whose name differs from the counted version just before, continuously; counted in the new version's cell. The other *_change_count columns likewise for their attribute.
 primary_activity_category_change_count   | integer               |           | not null |         | plain    |             |              | 
 secondary_activity_category_change_count | integer               |           | not null |         | plain    |             |              | 
 sector_change_count                      | integer               |           | not null |         | plain    |             |              | 
 legal_form_change_count                  | integer               |           | not null |         | plain    |             |              | 
 physical_region_change_count             | integer               |           | not null |         | plain    |             |              | 
 physical_country_change_count            | integer               |           | not null |         | plain    |             |              | 
 physical_address_change_count            | integer               |           | not null |         | plain    |             |              | 
 unit_size_change_count                   | integer               |           | not null |         | plain    |             |              | 
 status_change_count                      | integer               |           | not null |         | plain    |             |              | 
 stats_delta                              | jsonb                 |           |          |         | extended |             |              | The stats of the counted versions starting (in) and ending (out) here, as a jsonb_stats stats_delta; the stock of stats at a month end is their sum up to it. NULL when the month changes no stats.
 stats_ended_month                        | jsonb                 |           |          |         | extended |             |              | Stats of counted versions that end inside this month with no later version starting in it: the unit's latest version overlapping a month period, which that month's stats include although it is not in the stock at the month end.
 stats_ended_year                         | jsonb                 |           |          |         | extended |             |              | As stats_ended_month, for year periods: versions ending inside the year with no later version starting in it, stored in the month they end.
 unit_ids                                 | integer[]             |           | not null |         | extended |             |              | Units contributing to this row, sorted. A unit leaves when its contribution is removed; the row is deleted when no unit remains.
Indexes:
    "statistical_history_facet_delta_key" UNIQUE, btree (unit_type, primary_activity_category_path, secondary_activity_category_path, sector_path, legal_form_id, physical_region_path, physical_country_id, unit_size_id, status_id, on_month) NULLS NOT DISTINCT
    "statistical_history_facet_delta_unit_type_on_month_idx" btree (unit_type, on_month)
Policies:
    POLICY "statistical_history_facet_delta_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "statistical_history_facet_delta_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "statistical_history_facet_delta_regular_user_read" FOR SELECT
      TO regular_user
      USING (true)
Not-null constraints:
    "statistical_history_facet_delta_unit_type_not_null" NOT NULL "unit_type"
    "statistical_history_facet_delta_on_month_not_null" NOT NULL "on_month"
    "statistical_history_facet_delta_exists_added_count_not_null" NOT NULL "exists_added_count"
    "statistical_history_facet_delta_exists_removed_count_not_null" NOT NULL "exists_removed_count"
    "statistical_history_facet_delta_countable_added_count_not_null" NOT NULL "countable_added_count"
    "statistical_history_facet_delt_countable_removed_count_not_null" NOT NULL "countable_removed_count"
    "statistical_history_facet_delta_exists_moved_in_count_not_null" NOT NULL "exists_moved_in_count"
    "statistical_history_facet_delta_exists_moved_out_count_not_null" NOT NULL "exists_moved_out_count"
    "statistical_history_facet_del_countable_moved_in_count_not_null" NOT NULL "countable_moved_in_count"
    "statistical_history_facet_de_countable_moved_out_count_not_null" NOT NULL "countable_moved_out_count"
    "statistical_history_facet_delta_births_not_null" NOT NULL "births"
    "statistical_history_facet_delta_deaths_not_null" NOT NULL "deaths"
    "statistical_history_facet_delta_name_change_count_not_null" NOT NULL "name_change_count"
    "statistical_history_facet_d_primary_activity_category__not_null" NOT NULL "primary_activity_category_change_count"
    "statistical_history_facet_d_secondary_activity_categor_not_null" NOT NULL "secondary_activity_category_change_count"
    "statistical_history_facet_delta_sector_change_count_not_null" NOT NULL "sector_change_count"
    "statistical_history_facet_delt_legal_form_change_count_not_null" NOT NULL "legal_form_change_count"
    "statistical_history_facet_d_physical_region_change_cou_not_null" NOT NULL "physical_region_change_count"
    "statistical_history_facet_d_physical_country_change_co_not_null" NOT NULL "physical_country_change_count"
    "statistical_history_facet_d_physical_address_change_co_not_null" NOT NULL "physical_address_change_count"
    "statistical_history_facet_delta_unit_size_change_count_not_null" NOT NULL "unit_size_change_count"
    "statistical_history_facet_delta_status_change_count_not_null" NOT NULL "status_change_count"
    "statistical_history_facet_delta_unit_ids_not_null" NOT NULL "unit_ids"
Access method: heap

```

**Comment:** What changed per cell (unit_type and the facet dimensions) and month (on_month), counted from each unit's versions. Every column adds up: the stock of a cell at a month end is the sum up to it of exists_added_count - exists_removed_count + exists_moved_in_count - exists_moved_out_count (countable_* likewise), the changes of a period are the sum of its months, and a year is the sum of its months. Maintained by worker.derive_statistical_history_facet_delta and worker.statistical_history_facet_delta_reduce; read through statistical_history, statistical_history_facet, statistical_history_for and statistical_history_drilldown.
