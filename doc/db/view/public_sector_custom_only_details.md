```sql
                       View "public.sector_custom_only"
   Column    | Type  | Collation | Nullable | Default | Storage  | Description 
-------------+-------+-----------+----------+---------+----------+-------------
 path        | ltree |           |          |         | extended | 
 name        | text  |           |          |         | extended | 
 description | text  |           |          |         | extended | 
View definition:
 SELECT path,
    name,
    description
   FROM sector ac
  WHERE enabled AND custom
  ORDER BY path;
Triggers:
    sector_custom_only_prepare_trigger BEFORE INSERT ON sector_custom_only FOR EACH STATEMENT EXECUTE FUNCTION admin.sector_custom_only_prepare()
    sector_custom_only_upsert INSTEAD OF INSERT ON sector_custom_only FOR EACH ROW EXECUTE FUNCTION admin.sector_custom_only_upsert()
Options: security_invoker=on

```
