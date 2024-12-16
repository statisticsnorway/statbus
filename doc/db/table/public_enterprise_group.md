```sql
                                                      Table "public.enterprise_group"
          Column          |           Type           | Collation | Nullable |                            Default                            
--------------------------+--------------------------+-----------+----------+---------------------------------------------------------------
 id                       | integer                  |           | not null | nextval('enterprise_group_id_seq'::regclass)
 valid_after              | date                     |           | not null | generated always as ((valid_from - '1 day'::interval)) stored
 valid_from               | date                     |           | not null | CURRENT_DATE
 valid_to                 | date                     |           | not null | 'infinity'::date
 active                   | boolean                  |           | not null | true
 short_name               | character varying(16)    |           |          | 
 name                     | character varying(256)   |           |          | 
 created_at               | timestamp with time zone |           | not null | statement_timestamp()
 enterprise_group_type_id | integer                  |           |          | 
 telephone_no             | text                     |           |          | 
 email_address            | text                     |           |          | 
 web_address              | text                     |           |          | 
 contact_person           | text                     |           |          | 
 notes                    | text                     |           |          | 
 edit_by_user_id          | integer                  |           | not null | 
 edit_comment             | text                     |           |          | 
 unit_size_id             | integer                  |           |          | 
 data_source_id           | integer                  |           |          | 
 reorg_references         | text                     |           |          | 
 reorg_date               | timestamp with time zone |           |          | 
 reorg_type_id            | integer                  |           |          | 
 foreign_participation_id | integer                  |           |          | 
Indexes:
    "enterprise_group_id_daterange_excl" EXCLUDE USING gist (id WITH =, daterange(valid_after, valid_to, '[)'::text) WITH &&) DEFERRABLE
    "enterprise_group_id_valid_after_valid_to_key" UNIQUE CONSTRAINT, btree (id, valid_after, valid_to) DEFERRABLE
    "ix_enterprise_group_data_source_id" btree (data_source_id)
    "ix_enterprise_group_enterprise_group_type_id" btree (enterprise_group_type_id)
    "ix_enterprise_group_foreign_participation_id" btree (foreign_participation_id)
    "ix_enterprise_group_name" btree (name)
    "ix_enterprise_group_reorg_type_id" btree (reorg_type_id)
    "ix_enterprise_group_size_id" btree (unit_size_id)
Check constraints:
    "enterprise_group_valid_check" CHECK (valid_after < valid_to)
Foreign-key constraints:
    "enterprise_group_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id)
    "enterprise_group_enterprise_group_type_id_fkey" FOREIGN KEY (enterprise_group_type_id) REFERENCES enterprise_group_type(id)
    "enterprise_group_foreign_participation_id_fkey" FOREIGN KEY (foreign_participation_id) REFERENCES foreign_participation(id)
    "enterprise_group_reorg_type_id_fkey" FOREIGN KEY (reorg_type_id) REFERENCES reorg_type(id)
    "enterprise_group_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
Policies:
    POLICY "enterprise_group_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "enterprise_group_regular_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'regular_user'::statbus_role_type))
    POLICY "enterprise_group_super_user_manage"
      TO authenticated
      USING (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
      WITH CHECK (auth.has_statbus_role(auth.uid(), 'super_user'::statbus_role_type))
Triggers:
    trigger_prevent_enterprise_group_id_update BEFORE UPDATE OF id ON enterprise_group FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()

```
