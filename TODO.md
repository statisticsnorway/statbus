# Import Job Data Validation Implementation Plan

## Overview
This document outlines the plan for implementing a robust data validation system for the import job process. The system will support both batch validation and interactive editing of import data.

## Architecture Decision
We will implement a **dual-column approach** where:
- Each column has both a typed version (`column_name`) and a raw version (`column_name_raw`)
- Validation errors are stored in a JSONB column (`validation_errors`)
- All data is stored in a single table for simplicity and atomic operations

## Implementation Tasks

### 1. Schema Enhancements
- [ ] Add `validation_errors` JSONB column to data table schema
- [ ] Ensure raw columns exist for all target columns (`column_name_raw`)
- [ ] Add validation state tracking to data table

### 2. Batch Validation Function
- [ ] Implement `admin.batch_validate_import_data` function
  - Process each column for all rows in a single pass
  - Convert raw values to typed values where possible
  - Capture validation errors in JSONB format
  - Update row validation state based on errors

### 3. Chunked Processing for Large Datasets
- [ ] Implement `admin.batch_validate_import_data_chunked` function
  - Process data in configurable batch sizes
  - Use FOR UPDATE SKIP LOCKED for concurrent processing
  - Track progress for visibility
  - Handle resumability if process is interrupted

### 4. Type-Specific Validation Rules
- [ ] Integer validation: Check for valid integer format
- [ ] Numeric validation: Check for valid numeric format and precision
- [ ] Date validation: Check for valid date format and range
- [ ] Boolean validation: Handle various boolean representations
- [ ] Text validation: Length limits and pattern validation
- [ ] Reference data validation: Check against lookup tables (activity codes, etc.)

### 5. Interactive Editing Support
- [ ] Implement `public.update_import_row` function
  - Accept job_id, row_id, column_name, and new_value
  - Validate single cell and update both raw and typed values
  - Update validation errors for the specific column
  - Track edit history with user information

### 6. Integration with Import Job Process
- [ ] Update `admin.import_job_analyse` function
  - Initialize validation structure
  - Call batch validation function
  - Generate validation summary
  - Update job state based on validation results

### 7. User Interface Considerations
- [ ] Provide validation summary at job level
- [ ] Show validation errors at row and column level
- [ ] Allow filtering/sorting by validation status
- [ ] Support bulk and individual corrections

### 8. Performance Optimizations
- [ ] Use regex pre-validation before type conversion
- [ ] Implement efficient batch processing
- [ ] Add appropriate indexes for validation queries
- [ ] Consider materialized views for validation summaries

## Code Examples

### Example: Batch Validation Function
```sql
CREATE FUNCTION admin.batch_validate_import_data(job_id INTEGER)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    job public.import_job;
    column_info RECORD;
    update_stmt TEXT;
    error_capture_stmt TEXT;
BEGIN
    -- Get job details
    SELECT * INTO job FROM public.import_job WHERE id = job_id;
    
    -- Process each column in a single pass
    FOR column_info IN (
        SELECT 
            target_column, 
            target_type
        FROM 
            public.import_information
        WHERE 
            job_id = job_id
            AND target_column IS NOT NULL
            AND target_type IS NOT NULL
        GROUP BY 
            target_column, 
            target_type
        ORDER BY 
            MIN(source_column_priority)
    ) LOOP
        -- 1. Update the typed column with converted values where possible
        update_stmt := format(
            'UPDATE public.%I SET
                %I = CASE 
                    WHEN pg_typeof(%I_raw) = ''text''::regtype AND %I_raw = '''' THEN NULL
                    ELSE %s
                END
            WHERE 
                state = ''pending''',
            job.data_table_name,
            column_info.target_column,
            column_info.target_column,
            column_info.target_column,
            CASE column_info.target_type
                WHEN 'integer' THEN format('
                    CASE 
                        WHEN %I_raw ~ ''^-?[0-9]+$'' THEN %I_raw::%s
                        ELSE NULL 
                    END', 
                    column_info.target_column, 
                    column_info.target_column,
                    column_info.target_type)
                -- Add other type conversions as needed
                ELSE format('%I_raw::%s', 
                    column_info.target_column,
                    column_info.target_type)
            END
        );
        
        EXECUTE update_stmt;
        
        -- 2. Capture validation errors
        error_capture_stmt := format(
            'UPDATE public.%I SET
                validation_errors = validation_errors || 
                CASE 
                    WHEN %I IS NULL AND %I_raw IS NOT NULL AND %I_raw <> '''' THEN
                        jsonb_build_object(%L, jsonb_build_object(
                            ''error'', ''Failed to convert to %s'',
                            ''value'', %I_raw,
                            ''expected'', %L
                        ))
                    ELSE ''{}''::jsonb
                END
            WHERE 
                state = ''pending''',
            job.data_table_name,
            column_info.target_column,
            column_info.target_column,
            column_info.target_column,
            column_info.target_column,
            column_info.target_type,
            column_info.target_column,
            column_info.target_type
        );
        
        EXECUTE error_capture_stmt;
    END LOOP;
    
    -- 3. Update row validation state based on errors
    EXECUTE format(
        'UPDATE public.%I SET
            state = CASE 
                WHEN jsonb_object_length(validation_errors) > 0 THEN ''error''
                ELSE ''validated''
            END
        WHERE 
            state = ''pending''',
        job.data_table_name
    );
END;
$$;
```

### Example: Interactive Row Update Function
```sql
CREATE FUNCTION public.update_import_row(
  job_id INTEGER,
  row_id INTEGER,
  column_name TEXT,
  new_value TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  validation_result JSONB;
  update_stmt TEXT;
  result JSONB;
  column_type TEXT;
  job public.import_job;
BEGIN
  -- Get job details
  SELECT * INTO job FROM public.import_job WHERE id = job_id;
  
  -- Get column type
  SELECT target_type INTO column_type
  FROM public.import_information
  WHERE job_id = job_id AND target_column = column_name
  LIMIT 1;
  
  -- Validate based on type
  BEGIN
    -- Try conversion
    EXECUTE format('SELECT %L::%s', new_value, column_type);
    validation_result := '{}'::jsonb;
  EXCEPTION WHEN OTHERS THEN
    validation_result := jsonb_build_object(
      'error', SQLERRM,
      'value', new_value,
      'expected', column_type
    );
  END;
  
  -- Update both raw and typed values
  update_stmt := format(
    'UPDATE public.%I SET 
      %I_raw = $1,
      %I = CASE WHEN $2 = ''{}'':jsonb THEN $1::%s ELSE NULL END,
      validation_errors = CASE 
        WHEN $2 = ''{}'':jsonb THEN validation_errors - $3
        ELSE validation_errors || jsonb_build_object($3, $2)
      END,
      last_edited_at = NOW(),
      last_edited_by = $4
    WHERE id = $5
    RETURNING validation_errors',
    job.data_table_name,
    column_name, column_name,
    column_type
  );
  
  -- Execute update
  EXECUTE update_stmt 
  INTO result
  USING 
    new_value, 
    validation_result, 
    column_name,
    (SELECT id FROM public.statbus_user WHERE uuid = auth.uid()),
    row_id;
  
  RETURN result;
END;
$$;
```

## Next Steps
1. Implement schema changes
2. Develop and test batch validation function
3. Integrate with import job process
4. Add interactive editing support
5. Enhance user interface for validation feedback
