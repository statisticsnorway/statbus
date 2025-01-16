```sql
                               Materialized view "public.legal_form_used"
 Column |  Type   | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------+---------+-----------+----------+---------+----------+-------------+--------------+-------------
 id     | integer |           |          |         | plain    |             |              | 
 code   | text    |           |          |         | extended |             |              | 
 name   | text    |           |          |         | extended |             |              | 
Indexes:
    "legal_form_used_key" UNIQUE, btree (code)
View definition:
 SELECT lf.id,
    lf.code,
    lf.name
   FROM legal_form lf
  WHERE (lf.id IN ( SELECT statistical_unit.legal_form_id
           FROM statistical_unit
          WHERE statistical_unit.legal_form_id IS NOT NULL)) AND lf.active
  ORDER BY lf.id;
Access method: heap

```
