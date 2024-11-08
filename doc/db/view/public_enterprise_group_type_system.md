```sql
   View "public.enterprise_group_type_system"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    upsert_enterprise_group_type_system INSTEAD OF INSERT ON enterprise_group_type_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_enterprise_group_type_system()

```
