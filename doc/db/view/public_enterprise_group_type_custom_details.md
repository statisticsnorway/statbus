```sql
               View "public.enterprise_group_type_custom"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT enterprise_group_type_available.code,
    enterprise_group_type_available.name
   FROM enterprise_group_type_available
  WHERE enterprise_group_type_available.custom = true;
Triggers:
    prepare_enterprise_group_type_custom BEFORE INSERT ON enterprise_group_type_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_enterprise_group_type_custom()
    upsert_enterprise_group_type_custom INSTEAD OF INSERT ON enterprise_group_type_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_enterprise_group_type_custom()
Options: security_invoker=on

```
