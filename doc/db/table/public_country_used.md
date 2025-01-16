```sql
      Materialized view "public.country_used"
 Column |  Type   | Collation | Nullable | Default 
--------+---------+-----------+----------+---------
 id     | integer |           |          | 
 iso_2  | text    |           |          | 
 name   | text    |           |          | 
Indexes:
    "country_used_key" UNIQUE, btree (iso_2)

```
