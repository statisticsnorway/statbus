```sql
        View "public.legal_reorg_type_system"
   Column    | Type | Collation | Nullable | Default 
-------------+------+-----------+----------+---------
 code        | text |           |          | 
 name        | text |           |          | 
 description | text |           |          | 
Triggers:
    upsert_legal_reorg_type_system INSTEAD OF INSERT ON legal_reorg_type_system FOR EACH ROW EXECUTE FUNCTION admin.upsert_legal_reorg_type_system()

```
