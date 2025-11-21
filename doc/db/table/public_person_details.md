```sql
                                                                 Table "public.person"
     Column     |           Type           | Collation | Nullable |           Default            | Storage  | Compression | Stats target | Description 
----------------+--------------------------+-----------+----------+------------------------------+----------+-------------+--------------+-------------
 id             | integer                  |           | not null | generated always as identity | plain    |             |              | 
 personal_ident | text                     |           |          |                              | extended |             |              | 
 country_id     | integer                  |           |          |                              | plain    |             |              | 
 created_at     | timestamp with time zone |           | not null | statement_timestamp()        | plain    |             |              | 
 given_name     | character varying(150)   |           |          |                              | extended |             |              | 
 middle_name    | character varying(150)   |           |          |                              | extended |             |              | 
 family_name    | character varying(150)   |           |          |                              | extended |             |              | 
 birth_date     | date                     |           |          |                              | plain    |             |              | 
 sex            | person_sex               |           |          |                              | plain    |             |              | 
 phone_number   | text                     |           |          |                              | extended |             |              | 
 mobile_number  | text                     |           |          |                              | extended |             |              | 
 address_part1  | character varying(200)   |           |          |                              | extended |             |              | 
 address_part2  | character varying(200)   |           |          |                              | extended |             |              | 
 address_part3  | character varying(200)   |           |          |                              | extended |             |              | 
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
      WITH CHECK (true)
Not-null constraints:
    "person_id_not_null" NOT NULL "id"
    "person_created_at_not_null" NOT NULL "created_at"
Triggers:
    trigger_prevent_person_id_update BEFORE UPDATE OF id ON person FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
