```sql
                                      Table "public.person"
     Column      |           Type           | Collation | Nullable |           Default            
-----------------+--------------------------+-----------+----------+------------------------------
 id              | integer                  |           | not null | generated always as identity
 country_id      | integer                  |           |          | 
 created_at      | timestamp with time zone |           | not null | statement_timestamp()
 given_name      | character varying(150)   |           |          | 
 middle_name     | character varying(150)   |           |          | 
 family_name     | character varying(150)   |           |          | 
 birth_date      | date                     |           |          | 
 sex             | person_sex               |           |          | 
 phone_number    | text                     |           |          | 
 mobile_number   | text                     |           |          | 
 address_part1   | character varying(200)   |           |          | 
 address_part2   | character varying(200)   |           |          | 
 address_part3   | character varying(200)   |           |          | 
 death_date      | date                     |           |          | 
 edit_comment    | character varying(512)   |           |          | 
 edit_by_user_id | integer                  |           | not null | auth.uid()
 edit_at         | timestamp with time zone |           | not null | statement_timestamp()
Indexes:
    "person_pkey" PRIMARY KEY, btree (id)
    "ix_person_country_id" btree (country_id)
    "ix_person_edit_by_user_id" btree (edit_by_user_id)
    "ix_person_given_name_surname" btree (given_name, middle_name, family_name)
Foreign-key constraints:
    "person_country_id_fkey" FOREIGN KEY (country_id) REFERENCES country(id)
    "person_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
Referenced by:
    TABLE "person_for_unit" CONSTRAINT "person_for_unit_person_id_fkey" FOREIGN KEY (person_id) REFERENCES person(id) ON DELETE RESTRICT
Policies:
    POLICY "person_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "person_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "person_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK ((edit_by_user_id = auth.uid()))
Triggers:
    trigger_prevent_person_id_update BEFORE UPDATE OF id ON person FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
