```sql
                                                                         Table "public.enterprise_group"
          Column          |           Type           | Collation | Nullable |                   Default                    | Storage  | Compression | Stats target | Description 
--------------------------+--------------------------+-----------+----------+----------------------------------------------+----------+-------------+--------------+-------------
 id                       | integer                  |           | not null | nextval('enterprise_group_id_seq'::regclass) | plain    |             |              | 
 valid_from               | date                     |           | not null |                                              | plain    |             |              | 
 valid_to                 | date                     |           | not null |                                              | plain    |             |              | 
 valid_until              | date                     |           | not null |                                              | plain    |             |              | 
 short_name               | character varying(16)    |           |          |                                              | extended |             |              | 
 name                     | character varying(256)   |           |          |                                              | extended |             |              | 
 enterprise_group_type_id | integer                  |           |          |                                              | plain    |             |              | 
 contact_person           | text                     |           |          |                                              | extended |             |              | 
 edit_comment             | character varying(512)   |           |          |                                              | extended |             |              | 
 edit_by_user_id          | integer                  |           | not null |                                              | plain    |             |              | 
 edit_at                  | timestamp with time zone |           | not null | statement_timestamp()                        | plain    |             |              | 
 unit_size_id             | integer                  |           |          |                                              | plain    |             |              | 
 data_source_id           | integer                  |           |          |                                              | plain    |             |              | 
 reorg_references         | text                     |           |          |                                              | extended |             |              | 
 reorg_date               | timestamp with time zone |           |          |                                              | plain    |             |              | 
 reorg_type_id            | integer                  |           |          |                                              | plain    |             |              | 
 foreign_participation_id | integer                  |           |          |                                              | plain    |             |              | 
Indexes:
    "enterprise_group_pkey" PRIMARY KEY, btree (id, valid_from, valid_until) DEFERRABLE
    "enterprise_group_id_idx" btree (id)
    "enterprise_group_id_valid_excl" EXCLUDE USING gist (id WITH =, daterange(valid_from, valid_until) WITH &&) DEFERRABLE
    "ix_enterprise_group_data_source_id" btree (data_source_id)
    "ix_enterprise_group_edit_by_user_id" btree (edit_by_user_id)
    "ix_enterprise_group_enterprise_group_type_id" btree (enterprise_group_type_id)
    "ix_enterprise_group_foreign_participation_id" btree (foreign_participation_id)
    "ix_enterprise_group_name" btree (name)
    "ix_enterprise_group_reorg_type_id" btree (reorg_type_id)
    "ix_enterprise_group_size_id" btree (unit_size_id)
Check constraints:
    "enterprise_group_valid_check" CHECK (valid_from < valid_until AND valid_from > '-infinity'::date)
Foreign-key constraints:
    "enterprise_group_data_source_id_fkey" FOREIGN KEY (data_source_id) REFERENCES data_source(id)
    "enterprise_group_edit_by_user_id_fkey" FOREIGN KEY (edit_by_user_id) REFERENCES auth."user"(id) ON DELETE RESTRICT
    "enterprise_group_enterprise_group_type_id_fkey" FOREIGN KEY (enterprise_group_type_id) REFERENCES enterprise_group_type(id)
    "enterprise_group_foreign_participation_id_fkey" FOREIGN KEY (foreign_participation_id) REFERENCES foreign_participation(id)
    "enterprise_group_reorg_type_id_fkey" FOREIGN KEY (reorg_type_id) REFERENCES reorg_type(id)
    "enterprise_group_unit_size_id_fkey" FOREIGN KEY (unit_size_id) REFERENCES unit_size(id)
Policies:
    POLICY "enterprise_group_admin_user_manage"
      TO admin_user
      USING (true)
      WITH CHECK (true)
    POLICY "enterprise_group_authenticated_read" FOR SELECT
      TO authenticated
      USING (true)
    POLICY "enterprise_group_regular_user_manage"
      TO regular_user
      USING (true)
      WITH CHECK (true)
Triggers:
    enterprise_group_synchronize_temporal_columns_trigger BEFORE INSERT OR UPDATE OF valid_from, valid_until, valid_to ON enterprise_group FOR EACH ROW EXECUTE FUNCTION sql_saga.synchronize_temporal_columns('valid_from', 'valid_until', 'valid_to', 'null', 'date', 't')
    trigger_prevent_enterprise_group_id_update BEFORE UPDATE OF id ON enterprise_group FOR EACH ROW EXECUTE FUNCTION admin.prevent_id_update()
Access method: heap

```
