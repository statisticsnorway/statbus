```sql
   View "public.foreign_participation_system"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    upsert_foreign_participation_system INSTEAD OF INSERT ON foreign_participation_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_foreign_participation_system()

```
