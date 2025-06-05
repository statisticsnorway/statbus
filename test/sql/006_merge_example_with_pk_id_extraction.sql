BEGIN;

-- Improved example of using the MERGE command in PostgreSQL (version 15+)
-- Demonstrates how to log MERGE operations (INSERT/UPDATE) to a separate table,
-- and how to write back the generated ID to the source table, all within a single CTE chain.

-- Step 0: Clean up and define table structures

DROP TABLE IF EXISTS merge_log;
DROP TABLE IF EXISTS source_products;
DROP TABLE IF EXISTS target_products;

-- Target table
CREATE TABLE target_products (
    product_id SERIAL PRIMARY KEY, -- PK is now auto-generated (SERIAL)
    product_name VARCHAR(255) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INT DEFAULT 0,
    last_modified_at TIMESTAMPTZ NOT NULL, -- Timestamp of the last modification in the source
    sync_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP -- Timestamp of the last synchronization
);

-- Source table
CREATE TABLE source_products (
    source_id SERIAL PRIMARY KEY, -- Source table's own unique primary key
    target_product_id_ref INT NULL, -- Reference to target_products.product_id. NULL for new products.
    product_name VARCHAR(255) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    stock_quantity INT DEFAULT 0,
    last_modified_at TIMESTAMPTZ NOT NULL -- Timestamp of the last modification in the source data
);

-- Result table for logging MERGE operations
CREATE TABLE merge_log (
    log_id SERIAL PRIMARY KEY,
    action_taken TEXT NOT NULL, -- 'INSERT' or 'UPDATE'
    source_table_pk INT, -- Reference to source_products.source_id
    target_table_pk INT, -- Reference to target_products.product_id (the generated/existing one)
    log_timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_source_products FOREIGN KEY (source_table_pk) REFERENCES source_products(source_id),
    CONSTRAINT fk_target_products FOREIGN KEY (target_table_pk) REFERENCES target_products(product_id)
);

-- Step 1: Insert initial data into the target table
INSERT INTO target_products (product_name, price, stock_quantity, last_modified_at, sync_at) VALUES
('Old Apple', 9.50, 100, '2023-01-01 10:00:00 UTC', '2023-01-15 12:00:00 UTC'),
('Banana', 5.00, 150, '2023-01-05 12:00:00 UTC', '2023-01-15 12:00:00 UTC'),
('Old Pear', 12.00, 80, '2023-01-02 08:00:00 UTC', '2023-01-15 12:00:00 UTC');

-- Step 2: Insert data into the source table
INSERT INTO source_products (target_product_id_ref, product_name, price, stock_quantity, last_modified_at) VALUES
(1, 'New Apple', 10.50, 90, '2023-01-20 14:00:00 UTC'),
(2, 'Banana', 5.00, 140, '2023-01-04 11:00:00 UTC'),
(NULL, 'Orange', 8.75, 120, '2023-01-20 15:00:00 UTC');

-- Displaying content BEFORE MERGE
\echo '--- Target table (target_products) BEFORE MERGE ---';
SELECT product_id, product_name, price, stock_quantity, last_modified_at, '<timestamp>'::text as sync_at FROM target_products ORDER BY product_id;
\echo '--- Source table (source_products) BEFORE MERGE ---';
SELECT * FROM source_products ORDER BY source_id;
\echo '--- Log table (merge_log) BEFORE MERGE ---';
SELECT log_id, action_taken, source_table_pk, target_table_pk, '<timestamp>'::text as log_timestamp FROM merge_log ORDER BY log_id;

-- Step 3: Perform MERGE, log operations, and update the source table in a single statement

\echo '--- Performing MERGE, logging to merge_log, and updating source_products.target_product_id_ref ---';
WITH source_data_prepared AS (
    SELECT
        s.source_id,
        s.target_product_id_ref,
        s.product_name,
        s.price,
        s.stock_quantity,
        s.last_modified_at AS source_last_modified_at,
        t.product_id AS existing_target_product_id,
        t.last_modified_at AS target_current_last_modified_at,
        CASE
            WHEN s.target_product_id_ref IS NULL THEN 'INSERT'
            WHEN t.product_id IS NULL THEN 'INSERT' -- Should not happen if target_product_id_ref is set, but safe check
            WHEN s.last_modified_at > t.last_modified_at THEN 'UPDATE'
            ELSE 'NO_ACTION'
        END AS potential_action
    FROM source_products s
    LEFT JOIN target_products t ON s.target_product_id_ref = t.product_id
),
actionable_source_data AS (
    SELECT *
    FROM source_data_prepared
    WHERE potential_action IN ('INSERT', 'UPDATE')
),
merged_output AS (
    MERGE INTO target_products AS t
    USING actionable_source_data AS s_input
    ON t.product_id = s_input.target_product_id_ref
    WHEN MATCHED AND s_input.potential_action = 'UPDATE' THEN
        UPDATE SET
            product_name = s_input.product_name,
            price = s_input.price,
            stock_quantity = s_input.stock_quantity,
            last_modified_at = s_input.source_last_modified_at,
            sync_at = CURRENT_TIMESTAMP -- Keep CURRENT_TIMESTAMP for actual operation
    WHEN NOT MATCHED AND s_input.potential_action = 'INSERT' THEN
        INSERT (product_name, price, stock_quantity, last_modified_at, sync_at)
        VALUES (s_input.product_name, s_input.price, s_input.stock_quantity, s_input.source_last_modified_at, CURRENT_TIMESTAMP) -- Keep CURRENT_TIMESTAMP
    RETURNING
        t.product_id AS final_target_id,
        s_input.source_id AS source_table_pk_from_merge, -- This is source_products.source_id
        s_input.potential_action AS action_performed
),
-- Step 4 (integrated): Insert the returned information into the log table and return key info
logged_actions AS (
    INSERT INTO merge_log (action_taken, source_table_pk, target_table_pk, log_timestamp)
    SELECT
        mo.action_performed,
        mo.source_table_pk_from_merge,
        mo.final_target_id,
        CURRENT_TIMESTAMP -- Keep CURRENT_TIMESTAMP for actual operation
    FROM merged_output mo
    RETURNING source_table_pk, target_table_pk, action_taken -- Make these available for the next CTE/operation
)
-- Step 5 (integrated): Update the source table with the generated target_id for INSERTED rows
UPDATE source_products sp
SET target_product_id_ref = la.target_table_pk
FROM logged_actions la
WHERE sp.source_id = la.source_table_pk
  AND la.action_taken = 'INSERT';
-- For 'Orange' (source_id=3), target_product_id_ref (which was NULL) will now be set to the generated product_id (e.g., 4).

-- Displaying content AFTER MERGE and source update
\echo '--- Target table (target_products) AFTER MERGE ---';
SELECT product_id, product_name, price, stock_quantity, last_modified_at, '<timestamp>'::text as sync_at FROM target_products ORDER BY product_id;
\echo '--- Source table (source_products) AFTER MERGE and source update ---';
SELECT * FROM source_products ORDER BY source_id;
\echo '--- Log table (merge_log) AFTER MERGE ---';
SELECT log_id, action_taken, source_table_pk, target_table_pk, '<timestamp>'::text as log_timestamp FROM merge_log ORDER BY log_id;

/*
Expected result (unchanged from the previous version, but achieved with a more integrated SQL statement):

In target_products:
- Product 1 (Apple): Updated. (product_id=1, name='New Apple', price=10.50, stock=90, last_modified='2023-01-20 14:00:00 UTC')
- Product 2 (Banana): Unchanged. (product_id=2, name='Banana', price=5.00, stock=150, last_modified='2023-01-05 12:00:00 UTC')
- Product 3 (Pear): Unchanged. (product_id=3, name='Old Pear', price=12.00, stock=80, last_modified='2023-01-02 08:00:00 UTC')
- Product 4 (Orange): Inserted. (product_id=4 (generated), name='Orange', price=8.75, stock=120, last_modified='2023-01-20 15:00:00 UTC')

In source_products (assuming source_id for 'New Apple' is 1, 'Banana' is 2, 'Orange' is 3):
- Row 1 ('New Apple'): target_product_id_ref=1
- Row 2 ('Banana'): target_product_id_ref=2
- Row 3 ('Orange'): target_product_id_ref will be updated from NULL to 4.

In merge_log:
- One row for the update of product 1: (action_taken='UPDATE', source_table_pk=1, target_table_pk=1, ...)
- One row for the insertion of product 4 ('Orange'): (action_taken='INSERT', source_table_pk=3, target_table_pk=4, ...)
*/

ABORT;
