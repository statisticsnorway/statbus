```sql
        View "public.person_role_system"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    upsert_person_role_system INSTEAD OF INSERT ON person_role_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_person_role_system()

```
