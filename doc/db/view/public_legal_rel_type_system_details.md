```sql
                     View "public.legal_rel_type_system"
   Column    | Type | Collation | Nullable | Default | Storage  | Description 
-------------+------+-----------+----------+---------+----------+-------------
 code        | text |           |          |         | extended | 
 name        | text |           |          |         | extended | 
 description | text |           |          |         | extended | 
View definition:
 SELECT code,
    name,
    description
   FROM legal_rel_type_enabled
  WHERE custom = false;
Triggers:
    upsert_legal_rel_type_system INSTEAD OF INSERT ON legal_rel_type_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_legal_rel_type_system()
Options: security_invoker=on

```
