```sql
                         View "public.region_7_levels_view"
      Column       | Type | Collation | Nullable | Default | Storage  | Description 
-------------------+------+-----------+----------+---------+----------+-------------
 Regional Code     | text |           |          |         | extended | 
 Regional Name     | text |           |          |         | extended | 
 District Code     | text |           |          |         | extended | 
 District Name     | text |           |          |         | extended | 
 County Code       | text |           |          |         | extended | 
 County Name       | text |           |          |         | extended | 
 Constituency Code | text |           |          |         | extended | 
 Constituency Name | text |           |          |         | extended | 
 Subcounty Code    | text |           |          |         | extended | 
 Subcounty Name    | text |           |          |         | extended | 
 Parish Code       | text |           |          |         | extended | 
 Parish Name       | text |           |          |         | extended | 
 Village Code      | text |           |          |         | extended | 
 Village Name      | text |           |          |         | extended | 
View definition:
 SELECT ''::text AS "Regional Code",
    ''::text AS "Regional Name",
    ''::text AS "District Code",
    ''::text AS "District Name",
    ''::text AS "County Code",
    ''::text AS "County Name",
    ''::text AS "Constituency Code",
    ''::text AS "Constituency Name",
    ''::text AS "Subcounty Code",
    ''::text AS "Subcounty Name",
    ''::text AS "Parish Code",
    ''::text AS "Parish Name",
    ''::text AS "Village Code",
    ''::text AS "Village Name";
Triggers:
    upsert_region_7_levels_view INSTEAD OF INSERT ON region_7_levels_view FOR EACH ROW EXECUTE FUNCTION admin.upsert_region_7_levels()
Options: security_invoker=on

```
