```sql
                     View "public.legal_form_custom"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT legal_form_available.code,
    legal_form_available.name
   FROM legal_form_available
  WHERE legal_form_available.custom = true;
Triggers:
    prepare_legal_form_custom BEFORE INSERT ON legal_form_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_legal_form_custom()
    upsert_legal_form_custom INSTEAD OF INSERT ON legal_form_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_legal_form_custom()
Options: security_invoker=on

```