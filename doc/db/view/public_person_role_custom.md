```sql
        View "public.person_role_custom"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    prepare_person_role_custom BEFORE INSERT ON person_role_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_person_role_custom()
    upsert_person_role_custom INSTEAD OF INSERT ON person_role_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_person_role_custom()

```
