```sql
           Materialized view "public.sector_used"
 Column |       Type        | Collation | Nullable | Default 
--------+-------------------+-----------+----------+---------
 id     | integer           |           |          | 
 path   | ltree             |           |          | 
 label  | character varying |           |          | 
 code   | character varying |           |          | 
 name   | text              |           |          | 
Indexes:
    "sector_used_key" UNIQUE, btree (path)

```
