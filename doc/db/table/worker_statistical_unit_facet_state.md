```sql
                                                                                                                                                                 Table "worker.statistical_unit_facet_state"
    Column     |   Type    | Collation | Nullable |     Default     | Storage  | Compression | Stats target |                                                                                                                          Description                                                                                                                           
---------------+-----------+-----------+----------+-----------------+----------+-------------+--------------+----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 recount_all   | boolean   |           | not null | true            | plain    |             |              | Every facet must be recounted: a derive rewrote all of public.statistical_unit_facet_staging (a full recalculation, or staging found empty), and no reduce has committed since.
 recount_slots | integer[] |           | not null | '{}'::integer[] | extended |             |              | Dirty hash slots of the partial derives since the last reduce committed: the slots of the units those cycles changed. The facet keys staged in them now are the facets the units entered; worker.statistical_unit_facet_recount_keys holds the ones they left.
Indexes:
    "statistical_unit_facet_state_single_row" UNIQUE, btree ((true))
Not-null constraints:
    "statistical_unit_facet_state_recount_all_not_null" NOT NULL "recount_all"
    "statistical_unit_facet_state_recount_slots_not_null" NOT NULL "recount_slots"
Access method: heap

```

**Comment:** One row: what worker.statistical_unit_facet_reduce must recount, set by worker.derive_statistical_unit_facet and reset by the reduce that recounts it, in the reduce's transaction. A derive only adds to it, so the work of a cycle whose reduce did not commit is done by the next reduce.
