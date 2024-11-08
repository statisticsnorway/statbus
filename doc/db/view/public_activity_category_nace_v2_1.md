```sql
               View "public.activity_category_nace_v2_1"
   Column    |          Type          | Collation | Nullable | Default 
-------------+------------------------+-----------+----------+---------
 standard    | character varying(16)  |           |          | 
 path        | ltree                  |           |          | 
 label       | character varying      |           |          | 
 code        | character varying      |           |          | 
 name        | character varying(256) |           |          | 
 description | text                   |           |          | 
Triggers:
    delete_stale_activity_category_nace_v2_1 AFTER INSERT ON activity_category_nace_v2_1 FOR EACH STATEMENT EXECUTE FUNCTION admin.delete_stale_activity_category()
    upsert_activity_category_nace_v2_1 INSTEAD OF INSERT ON activity_category_nace_v2_1 FOR EACH ROW EXECUTE FUNCTION admin.upsert_activity_category('nace_v2.1')

```
