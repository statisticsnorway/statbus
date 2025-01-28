```sql
                                      Table "public.person"
     Column     |           Type           | Collation | Nullable |           Default            
----------------+--------------------------+-----------+----------+------------------------------
 id             | integer                  |           | not null | generated always as identity
 personal_ident | text                     |           |          | 
 country_id     | integer                  |           |          | 
 created_at     | timestamp with time zone |           | not null | statement_timestamp()
 given_name     | character varying(150)   |           |          | 
 middle_name    | character varying(150)   |           |          | 
 family_name    | character varying(150)   |           |          | 
 birth_date     | date                     |           |          | 
 sex            | person_sex               |           |          | 
 phone_number   | text                     |           |          | 
 mobile_number  | text                     |           |          | 
 address_part1  | character varying(200)   |           |          | 
 address_part2  | character varying(200)   |           |          | 
 address_part3  | character varying(200)   |           |          | 
Indexes:
    "person_pkey" PRIMARY KEY, btree (id)
    "ix_person_country_id" btree (country_id)
    "ix_person_given_name_surname" btree (given_name, middle_name, family_name)
    "person_personal_ident_key" UNIQUE CONSTRAINT, btree (personal_ident)
Foreign-key constraints:
    "person_country_id_fkey" FOREIGN KEY (country_id) REFERENCES country(id)
Referenced by:
    TABLE "person_for_unit" CONSTRAINT "person_for_unit_person_id_fkey" FOREIGN KEY (person_id) REFERENCES person(id) ON DELETE RESTRICT
Policies:
    POLICY "person_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "person_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "person_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_person_id_update BEFORE UPDATE OF id ON person FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
