```sql
                    View "public.person_role_custom"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT code,
    name
   FROM person_role_available
  WHERE custom = true;
Triggers:
    prepare_person_role_custom BEFORE INSERT ON person_role_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_person_role_custom()
    upsert_person_role_custom INSTEAD OF INSERT ON person_role_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_person_role_custom()
Options: security_invoker=on

```
