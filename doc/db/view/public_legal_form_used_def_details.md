```sql
                     View "public.legal_form_used_def"
 Column |  Type   | Collation | Nullable | Default | Storage  | Description 
--------+---------+-----------+----------+---------+----------+-------------
 id     | integer |           |          |         | plain    | 
 code   | text    |           |          |         | extended | 
 name   | text    |           |          |         | extended | 
View definition:
 SELECT lf.id,
    lf.code,
    lf.name
   FROM legal_form lf
  WHERE (lf.id IN ( SELECT statistical_unit.legal_form_id
           FROM statistical_unit
          WHERE statistical_unit.legal_form_id IS NOT NULL)) AND lf.active
  ORDER BY lf.id;

```
