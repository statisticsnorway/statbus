```sql
        View "public.legal_form_system"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    upsert_legal_form_system INSTEAD OF INSERT ON legal_form_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_legal_form_system()

```
