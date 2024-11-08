```sql
        View "public.legal_form_custom"
 Column | Type | Collation | Nullable | Default 
--------+------+-----------+----------+---------
 code   | text |           |          | 
 name   | text |           |          | 
Triggers:
    prepare_legal_form_custom BEFORE INSERT ON legal_form_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_legal_form_custom()
    upsert_legal_form_custom INSTEAD OF INSERT ON legal_form_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_legal_form_custom()

```
