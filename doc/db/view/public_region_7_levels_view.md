```sql
            View "public.region_7_levels_view"
      Column       | Type | Collation | Nullable | Default 
-------------------+------+-----------+----------+---------
 Regional Code     | text |           |          | 
 Regional Name     | text |           |          | 
 District Code     | text |           |          | 
 District Name     | text |           |          | 
 County Code       | text |           |          | 
 County Name       | text |           |          | 
 Constituency Code | text |           |          | 
 Constituency Name | text |           |          | 
 Subcounty Code    | text |           |          | 
 Subcounty Name    | text |           |          | 
 Parish Code       | text |           |          | 
 Parish Name       | text |           |          | 
 Village Code      | text |           |          | 
 Village Name      | text |           |          | 
Triggers:
    upsert_region_7_levels_view INSTEAD OF INSERT ON region_7_levels_view FOR EACH ROW EXECUTE FUNCTION admin.upsert_region_7_levels()

```
