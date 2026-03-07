```sql
                           View "public.power_group_def"
     Column     |  Type   | Collation | Nullable | Default | Storage | Description 
----------------+---------+-----------+----------+---------+---------+-------------
 power_group_id | integer |           |          |         | plain   | 
 depth          | integer |           |          |         | plain   | 
 width          | bigint  |           |          |         | plain   | 
 reach          | bigint  |           |          |         | plain   | 
View definition:
 SELECT power_group_id,
    max(power_level) - 1 AS depth,
    count(*) FILTER (WHERE power_level = 2) AS width,
    count(*) - 1 AS reach
   FROM power_group_membership pgm
  GROUP BY power_group_id;
Options: security_invoker=on

```
