```sql
                         View "public.country_view"
 Column  |  Type   | Collation | Nullable | Default | Storage  | Description 
---------+---------+-----------+----------+---------+----------+-------------
 id      | integer |           |          |         | plain    | 
 iso_2   | text    |           |          |         | extended | 
 iso_3   | text    |           |          |         | extended | 
 iso_num | text    |           |          |         | extended | 
 name    | text    |           |          |         | extended | 
 enabled | boolean |           |          |         | plain    | 
 custom  | boolean |           |          |         | plain    | 
View definition:
 SELECT id,
    iso_2,
    iso_3,
    iso_num,
    name,
    enabled,
    custom
   FROM country;
Triggers:
    delete_stale_country_view AFTER INSERT ON country_view FOR EACH STATEMENT EXECUTE FUNCTION admin.delete_stale_country()
    upsert_country_view INSTEAD OF INSERT ON country_view FOR EACH ROW EXECUTE FUNCTION admin.upsert_country()
Options: security_invoker=on

```
