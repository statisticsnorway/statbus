```sql
                         View "public.country_view"
 Column  |  Type   | Collation | Nullable | Default | Storage  | Description 
---------+---------+-----------+----------+---------+----------+-------------
 id      | integer |           |          |         | plain    | 
 iso_2   | text    |           |          |         | extended | 
 iso_3   | text    |           |          |         | extended | 
 iso_num | text    |           |          |         | extended | 
 name    | text    |           |          |         | extended | 
 active  | boolean |           |          |         | plain    | 
 custom  | boolean |           |          |         | plain    | 
View definition:
 SELECT country.id,
    country.iso_2,
    country.iso_3,
    country.iso_num,
    country.name,
    country.active,
    country.custom
   FROM country;
Triggers:
    delete_stale_country_view AFTER INSERT ON country_view FOR EACH STATEMENT EXECUTE FUNCTION admin.delete_stale_country()
    upsert_country_view INSTEAD OF INSERT ON country_view FOR EACH ROW EXECUTE FUNCTION admin.upsert_country()
Options: security_invoker=on

```