```sql
                       View "public.country_used_def"
 Column |  Type   | Collation | Nullable | Default | Storage  | Description 
--------+---------+-----------+----------+---------+----------+-------------
 id     | integer |           |          |         | plain    | 
 iso_2  | text    |           |          |         | extended | 
 name   | text    |           |          |         | extended | 
View definition:
 SELECT id,
    iso_2,
    name
   FROM country c
  WHERE (id IN ( SELECT statistical_unit.physical_country_id
           FROM statistical_unit
          WHERE statistical_unit.physical_country_id IS NOT NULL)) AND active
  ORDER BY id;

```
