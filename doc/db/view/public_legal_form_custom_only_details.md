```sql
                  View "public.legal_form_custom_only"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT ac.code,
    ac.name
   FROM legal_form ac
  WHERE ac.active AND ac.custom
  ORDER BY ac.code;
Triggers:
    legal_form_custom_only_prepare_trigger BEFORE INSERT ON legal_form_custom_only FOR EACH STATEMENT EXECUTE FUNCTION admin.legal_form_custom_only_prepare()
    legal_form_custom_only_upsert INSTEAD OF INSERT ON legal_form_custom_only FOR EACH ROW EXECUTE FUNCTION admin.legal_form_custom_only_upsert()
Options: security_invoker=on

```