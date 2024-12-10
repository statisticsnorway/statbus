```sql
                       Table "auth.one_time_tokens"
   Column   |            Type             | Collation | Nullable | Default 
------------+-----------------------------+-----------+----------+---------
 id         | uuid                        |           | not null | 
 user_id    | uuid                        |           | not null | 
 token_type | auth.one_time_token_type    |           | not null | 
 token_hash | text                        |           | not null | 
 relates_to | text                        |           | not null | 
 created_at | timestamp without time zone |           | not null | now()
 updated_at | timestamp without time zone |           | not null | now()
Indexes:
    "one_time_tokens_pkey" PRIMARY KEY, btree (id)
    "one_time_tokens_relates_to_hash_idx" hash (relates_to)
    "one_time_tokens_token_hash_hash_idx" hash (token_hash)
    "one_time_tokens_user_id_token_type_key" UNIQUE, btree (user_id, token_type)
Check constraints:
    "one_time_tokens_token_hash_check" CHECK (char_length(token_hash) > 0)
Foreign-key constraints:
    "one_time_tokens_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE
Policies (row security enabled): (none)

```
