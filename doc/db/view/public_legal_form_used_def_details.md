```sql
                     View "public.legal_form_used_def"
 Column |  Type   | Collation | Nullable | Default | Storage  | Description 
--------+---------+-----------+----------+---------+----------+-------------
 id     | integer |           |          |         | plain    | 
 code   | text    |           |          |         | extended | 
 name   | text    |           |          |         | extended | 
View definition:
 SELECT id,
    code,
    name
   FROM legal_form lf
  WHERE (id IN ( SELECT statistical_unit.legal_form_id
           FROM statistical_unit
          WHERE statistical_unit.legal_form_id IS NOT NULL)) AND active
  ORDER BY id;

```
