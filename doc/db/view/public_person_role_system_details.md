```sql
                    View "public.person_role_system"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT person_role_available.code,
    person_role_available.name
   FROM person_role_available
  WHERE person_role_available.custom = false;
Triggers:
    upsert_person_role_system INSTEAD OF INSERT ON person_role_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_person_role_system()
Options: security_invoker=on

```
