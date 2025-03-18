 # Background Update of Timeline Tables Implementation Plan

 ## Overview
 This document outlines a plan to optimize the timeline views by converting them to physical tables wi
 proper indices, maintained by a background worker. This approach will significantly improve query
 performance while maintaining the same logical structure.

 ## Current Architecture
 Currently, we have several views that build on each other:
 - `timepoints` - Identifies significant points in time when statistical units change
 - `timesegments` - Creates time segments based on timepoints
 - `timeline_establishment` - Detailed view of establishments over time
 - `timeline_legal_unit` - Detailed view of legal units over time
 - `timeline_enterprise` - Detailed view of enterprises over time

 These views use complex CTEs (some with MATERIALIZED hints) but lack proper indices for efficient
 joins.

 ## Proposed Architecture
 1. Convert each view into a definition view (`*_def`) and a physical UNLOGGED table
 2. Add appropriate indices to the physical tables
 3. Use the existing worker framework to keep tables in sync with source data
 4. Use the table name directly (replacing the original view name)
 5. No compatibility views needed as tables completely replace the original views

 ## Implementation Tasks by File

 ### Task 1: Create Definition Views and Tables
 **Agent 1: Timepoints and Timesegments**
 - Modify `migrations/20240227000000_create_timepoints.up.sql`:
   - Rename existing view to `timepoints_def`
   - Create physical `timepoints` table with indices
   - Create simple view `timepoints` that selects from the table
 - Modify `migrations/20240228000000_create_view_timesegments.up.sql`:
   - Similar approach for timesegments

 **Agent 2: Timeline Establishment**
 - Modify `migrations/20240305000000_create_timeline_establishment.up.sql`:
   - Rename existing view to `timeline_establishment_def`
   - Create physical `timeline_establishment` table with indices
   - Create simple view `timeline_establishment` that selects from the table

 **Agent 3: Timeline Legal Unit**
 - Modify `migrations/20240306000000_create_timeline_legal_unit.up.sql`:
   - Rename existing view to `timeline_legal_unit_def`
   - Create physical `timeline_legal_unit` table with indices
   - Create simple view `timeline_legal_unit` that selects from the table

 **Agent 4: Timeline Enterprise**
 - Modify `migrations/20240307000000_create_timeline_enterprise.up.sql`:
   - Rename existing view to `timeline_enterprise_def`
   - Create physical `timeline_enterprise` table with indices
   - Create simple view `timeline_enterprise` that selects from the table

 ### Task 2: Create Worker Commands and Handlers
 **Agent 5: Worker Infrastructure**
 - Modify `migrations/20250213100637_create_worker_infrastructure.up.sql`:
   - Add new commands to the registry
   - Create command handlers for refreshing each table
   - Create enqueue functions for each refresh operation
   - Implement dependency chain (timepoints → timesegments → establishment → legal_unit → enterprise)

 ## Implementation Details

 ### Table Structure and Indices
 For each table, create:
 1. UNLOGGED tables for better performance
 2. Primary key on (unit_type, unit_id, valid_after)
 3. Index on date range using `USING gist (daterange(valid_after, valid_to, '(]'))`
 4. Indices on foreign keys (legal_unit_id, enterprise_id, etc.)
 5. Full-text search index on name column using `USING gin(search)`

 ### Refresh Strategy
 Use temporary tables during refresh to minimize the time between delete and insert operations:
 ```
 1. Create temporary table with new data
 2. Delete affected records from main table
 3. Insert from temporary table to main table in a single transaction
 ```

 This approach, similar to the one used in `worker.statistical_unit_refresh`, ensures data consistency
 and minimizes lock time.

 ### Dependency Chain
 Implement a chain of dependencies in the worker system where:
 1. Refreshing timepoints enqueues timesegments refresh
 2. Refreshing timesegments enqueues timeline_establishment refresh
 3. Refreshing timeline_establishment enqueues timeline_legal_unit refresh
 4. Refreshing timeline_legal_unit enqueues timeline_enterprise refresh
 
 Note: All dependencies and database triggers are managed by the worker system.

 ### Incremental Updates
 Support both full refresh and incremental updates:
 - Full refresh: Truncate and rebuild entire table
 - Incremental: Only refresh records within a specific date range or for specific unit IDs

 ### Worker Integration
 The worker system will monitor changes to base tables (establishment, legal_unit, enterprise, activity, etc.) and
 automatically enqueue refresh tasks when data changes. No database triggers are used for this purpose.

 ## Performance Considerations
 1. **Materialized CTEs**: The current use of `MATERIALIZED` in CTEs doesn't provide index benefits.
 Physical tables will be much more efficient.
 2. **Date Range Operations**: The `&&` operator will benefit greatly from GiST indices on date ranges
 3. **Hierarchical Data**: The enterprise view depends on legal units and establishments, creating a
 multi-level dependency that benefits from proper indexing.
 4. **Batch Processing**: Use appropriate batch sizes for large refreshes to avoid excessive memory
 usage.
 5. **Lock Contention**: Minimize lock time by using temporary tables during refresh operations.

 ## Migration Path
 1. Create new definition views and tables
 2. Populate tables with initial data
 3. Create simple views with the original names
 4. Register worker commands and handlers
 5. Schedule initial refresh
 6. Test query performance before and after

 ## Testing Strategy
 1. Compare query results before and after implementation to ensure data consistency
 2. Measure query performance improvements
 3. Test incremental updates with various scenarios
 4. Verify worker task scheduling and execution
 5. Check for any lock contention during refresh operations
