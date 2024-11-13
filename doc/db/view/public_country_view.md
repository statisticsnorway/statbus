```sql
             View "public.country_view"
 Column  |  Type   | Collation | Nullable | Default 
---------+---------+-----------+----------+---------
 id      | integer |           |          | 
 iso_2   | text    |           |          | 
 iso_3   | text    |           |          | 
 iso_num | text    |           |          | 
 name    | text    |           |          | 
 active  | boolean |           |          | 
 custom  | boolean |           |          | 
Triggers:
    delete_stale_country_view AFTER INSERT ON country_view FOR EACH STATEMENT EXECUTE FUNCTION admin.delete_stale_country()
    upsert_country_view INSTEAD OF INSERT ON country_view FOR EACH ROW EXECUTE FUNCTION admin.upsert_country()

```
