```sql
           Materialized view "public.region_used"
 Column |       Type        | Collation | Nullable | Default 
--------+-------------------+-----------+----------+---------
 id     | integer           |           |          | 
 path   | ltree             |           |          | 
 level  | integer           |           |          | 
 label  | character varying |           |          | 
 code   | character varying |           |          | 
 name   | text              |           |          | 
Indexes:
    "region_used_key" UNIQUE, btree (path)

```
