```sql
                     View "public.legal_form_system"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT legal_form_available.code,
    legal_form_available.name
   FROM legal_form_available
  WHERE legal_form_available.custom = false;
Triggers:
    upsert_legal_form_system INSTEAD OF INSERT ON legal_form_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_legal_form_system()
Options: security_invoker=on

```
