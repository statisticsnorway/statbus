```sql
                                                                                                                                                  Table "public.statistical_history_facet_delta_staging"
                  Column                  |         Type          | Collation | Nullable | Default | Storage  | Compression | Stats target |                                                                                                 Description                                                                                                  
------------------------------------------+-----------------------+-----------+----------+---------+----------+-------------+--------------+--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 unit_id                                  | integer               |           | not null |         | plain    |             |              | 
 sign                                     | smallint              |           | not null |         | plain    |             |              | 
 unit_type                                | statistical_unit_type |           | not null |         | plain    |             |              | 
 primary_activity_category_path           | ltree                 |           |          |         | extended |             |              | 
 secondary_activity_category_path         | ltree                 |           |          |         | extended |             |              | 
 sector_path                              | ltree                 |           |          |         | extended |             |              | 
 legal_form_id                            | integer               |           |          |         | plain    |             |              | 
 physical_region_path                     | ltree                 |           |          |         | extended |             |              | 
 physical_country_id                      | integer               |           |          |         | plain    |             |              | 
 unit_size_id                             | integer               |           |          |         | plain    |             |              | 
 status_id                                | integer               |           |          |         | plain    |             |              | 
 on_month                                 | date                  |           | not null |         | plain    |             |              | 
 exists_added_count                       | integer               |           | not null |         | plain    |             |              | 
 exists_removed_count                     | integer               |           | not null |         | plain    |             |              | 
 countable_added_count                    | integer               |           | not null |         | plain    |             |              | 
 countable_removed_count                  | integer               |           | not null |         | plain    |             |              | 
 exists_moved_in_count                    | integer               |           | not null |         | plain    |             |              | 
 exists_moved_out_count                   | integer               |           | not null |         | plain    |             |              | 
 countable_moved_in_count                 | integer               |           | not null |         | plain    |             |              | 
 countable_moved_out_count                | integer               |           | not null |         | plain    |             |              | 
 births                                   | integer               |           | not null |         | plain    |             |              | 
 deaths                                   | integer               |           | not null |         | plain    |             |              | 
 name_change_count                        | integer               |           | not null |         | plain    |             |              | 
 primary_activity_category_change_count   | integer               |           | not null |         | plain    |             |              | 
 secondary_activity_category_change_count | integer               |           | not null |         | plain    |             |              | 
 sector_change_count                      | integer               |           | not null |         | plain    |             |              | 
 legal_form_change_count                  | integer               |           | not null |         | plain    |             |              | 
 physical_region_change_count             | integer               |           | not null |         | plain    |             |              | 
 physical_country_change_count            | integer               |           | not null |         | plain    |             |              | 
 physical_address_change_count            | integer               |           | not null |         | plain    |             |              | 
 unit_size_change_count                   | integer               |           | not null |         | plain    |             |              | 
 status_change_count                      | integer               |           | not null |         | plain    |             |              | 
 stats_delta                              | jsonb                 |           |          |         | extended |             |              | 
 stats_ended_month                        | jsonb                 |           |          |         | extended |             |              | 
 stats_ended_year                         | jsonb                 |           |          |         | extended |             |              | 
 generation                               | bigint                |           | not null |         | plain    |             |              | The cycle that staged the row (see worker.statistical_history_facet_delta_state). 0 for rows that are true when they commit: the subtraction of units deleted from statistical_unit in the same transaction.
Not-null constraints:
    "statistical_history_facet_delta_staging_unit_id_not_null" NOT NULL "unit_id"
    "statistical_history_facet_delta_staging_sign_not_null" NOT NULL "sign"
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
    "statistical_history_facet_delta_staging_generation_not_null" NOT NULL "generation"
Access method: heap

```

**Comment:** Signed per-unit rows staged by worker.derive_statistical_history_facet_delta_partition children for this cycle; worker.statistical_history_facet_delta_reduce adds them into public.statistical_history_facet_delta.
