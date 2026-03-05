```sql
         View "public.legal_rel_type_custom"
   Column    | Type | Collation | Nullable | Default 
-------------+------+-----------+----------+---------
 code        | text |           |          | 
 name        | text |           |          | 
 description | text |           |          | 
Triggers:
    prepare_legal_rel_type_custom BEFORE INSERT ON legal_rel_type_custom FOR EACH STATEMENT EXECUTE FUNCTION admin.prepare_legal_rel_type_custom()
    upsert_legal_rel_type_custom INSTEAD OF INSERT ON legal_rel_type_custom FOR EACH ROW EXECUTE FUNCTION admin.upsert_legal_rel_type_custom()

```
