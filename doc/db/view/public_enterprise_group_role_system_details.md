```sql
               View "public.enterprise_group_role_system"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT code,
    name
   FROM enterprise_group_role_available
  WHERE custom = false;
Triggers:
    upsert_enterprise_group_role_system INSTEAD OF INSERT ON enterprise_group_role_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_enterprise_group_role_system()
Options: security_invoker=on

```
