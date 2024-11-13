```sql
   View "public.enterprise_group_role_custom"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    prepare_enterprise_group_role_custom BEFORE INSERT ON enterprise_group_role_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_enterprise_group_role_custom()
    upsert_enterprise_group_role_custom INSTEAD OF INSERT ON enterprise_group_role_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_enterprise_group_role_custom()

```
