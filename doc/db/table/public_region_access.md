```sql
                                                  Table "public.region_access"
  Column   |  Type   | Collation | Nullable |           Default            | Storage | Compression | Stats target | Description 
-----------+---------+-----------+----------+------------------------------+---------+-------------+--------------+-------------
 id        | integer |           | not null | generated always as identity | plain   |             |              | 
 user_id   | integer |           | not null |                              | plain   |             |              | 
 region_id | integer |           | not null |                              | plain   |             |              | 
Indexes:
    "region_access_pkey" PRIMARY KEY, btree (id)
    "ix_region_access_region_id" btree (region_id)
    "ix_region_access_user_id" btree (user_id)
    "region_access_user_id_region_id_key" UNIQUE CONSTRAINT, btree (user_id, region_id)
Foreign-key constraints:
    "region_access_region_id_fkey" FOREIGN KEY (region_id) REFERENCES region(id) ON DELETE CASCADE
    "region_access_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth."user"(id) ON DELETE CASCADE
Policies:
    POLICY "region_access_admin_policy"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "region_access_read_policy" FOR SELECT
      TO authenticated
      USING (true)
Not-null constraints:
    "region_access_id_not_null" NOT NULL "id"
    "region_access_user_id_not_null" NOT NULL "user_id"
    "region_access_region_id_not_null" NOT NULL "region_id"
Triggers:
    trigger_prevent_region_access_id_update BEFORE UPDATE OF id ON region_access FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
