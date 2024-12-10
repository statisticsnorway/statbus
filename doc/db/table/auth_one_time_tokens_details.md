```sql
                                                  Table "auth.one_time_tokens"
   Column   |            Type             | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
------------+-----------------------------+-----------+----------+---------+----------+-------------+--------------+-------------
 id         | uuid                        |           | not null |         | plain    |             |              | 
 user_id    | uuid                        |           | not null |         | plain    |             |              | 
 token_type | auth.one_time_token_type    |           | not null |         | plain    |             |              | 
 token_hash | text                        |           | not null |         | extended |             |              | 
 relates_to | text                        |           | not null |         | extended |             |              | 
 created_at | timestamp without time zone |           | not null | now()   | plain    |             |              | 
 updated_at | timestamp without time zone |           | not null | now()   | plain    |             |              | 
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
Access method: heap

```
