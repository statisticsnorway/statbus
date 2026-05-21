```sql
                  View "public.power_group_type_custom"
 Column | Type | Collation | Nullable | Default | Storage  | Description 
--------+------+-----------+----------+---------+----------+-------------
 code   | text |           |          |         | extended | 
 name   | text |           |          |         | extended | 
View definition:
 SELECT code,
    name
   FROM power_group_type_enabled
  WHERE custom = true;
Triggers:
    prepare_power_group_type_custom BEFORE INSERT ON power_group_type_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_power_group_type_custom()
    upsert_power_group_type_custom INSTEAD OF INSERT ON power_group_type_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_power_group_type_custom()
Options: security_invoker=on

```
