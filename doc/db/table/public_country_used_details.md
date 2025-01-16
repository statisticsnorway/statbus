```sql
                                 Materialized view "public.country_used"
 Column |  Type   | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+---------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer |           |          |         | plain    |             |              | 
 iso_2  | text    |           |          |         | extended |             |              | 
 name   | text    |           |          |         | extended |             |              | 
Indexes:
    "country_used_key" UNIQUE, btree (iso_2)
View definition:
 SELECT c.id,
    c.iso_2,
    c.name
   FROM country c
  WHERE (c.id IN ( SELECT statistical_unit.physical_country_id
           FROM statistical_unit
          WHERE statistical_unit.physical_country_id IS NOT NULL)) AND c.active
  ORDER BY c.id;
Access method: heap

```
