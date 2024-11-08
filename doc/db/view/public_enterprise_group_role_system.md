```sql
   View "public.enterprise_group_role_system"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    upsert_enterprise_group_role_system INSTEAD OF INSERT ON enterprise_group_role_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_enterprise_group_role_system()

```
