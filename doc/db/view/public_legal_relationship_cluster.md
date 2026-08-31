```sql
                         View "public.legal_relationship_cluster"
        Column         |  Type   | Collation | Nullable | Default | Storage | Description 
-----------------------+---------+-----------+----------+---------+---------+-------------
 legal_relationship_id | integer |           |          |         | plain   | 
 power_group_id        | integer |           |          |         | plain   | 
View definition:
 SELECT id AS legal_relationship_id,
    derived_power_group_id AS power_group_id
   FROM legal_relationship lr
  WHERE derived_power_group_id IS NOT NULL;
Options: security_invoker=on

```

**Comment:** Maps each legal_relationship to its power group (reads materialized derived_power_group_id)
