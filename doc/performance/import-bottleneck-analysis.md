# Analysis: Real Cause of 32 Updates Per Row

## Executive Summary

The 32 updates per row are NOT caused by statistical variables (there are only 2: employees and turnover). Instead, they are caused by the import processing architecture that has **15-16 processing steps**, each potentially updating the row **2-3 times**.

## The Real Architecture

### Processing Steps (15 total for hovedenhet):

1. **valid_time** (priority 10) - Analyse only
2. **external_idents** (priority 15) - Analyse only  
3. **data_source** (priority 16) - Analyse only
4. **status** (priority 17) - Analyse only
5. **enterprise_link_for_legal_unit** (priority 18) - Analyse + Process
6. **legal_unit** (priority 20) - Analyse + Process
7. **physical_location** (priority 30) - Analyse + Process
8. **postal_location** (priority 40) - Analyse + Process
9. **primary_activity** (priority 50) - Analyse + Process
10. **secondary_activity** (priority 60) - Analyse + Process
11. **contact** (priority 70) - Analyse + Process
12. **statistical_variables** (priority 80) - Analyse + Process
13. **tags** (priority 90) - Analyse + Process
14. **edit_info** (priority 100) - Analyse only
15. **metadata** (priority 110) - No procedures

### Update Pattern Per Step

Each step performs:
1. **Priority Update**: `UPDATE ... SET last_completed_priority = N`
2. **State Updates** (if has analyse): `UPDATE ... SET state = 'analysing'`
3. **State Updates** (if has process): `UPDATE ... SET state = 'processing'`

### Total Updates Calculation

- **Steps with Analyse only (5 steps)**: 2 updates each = 10 updates
- **Steps with Analyse + Process (9 steps)**: 3 updates each = 27 updates
- **Metadata step (1 step)**: 1 update = 1 update
- **Total**: 10 + 27 + 1 = **38 updates per row**

The observed ~32 updates likely comes from some optimizations or skipped steps in practice.

## Why This Architecture?

The step-based architecture is actually clever for:
1. **Modularity**: Each aspect (location, activity, etc.) is handled independently
2. **Error Recovery**: Can restart from any step
3. **Flexibility**: Can add/remove steps per import definition
4. **Parallelization**: Steps at same priority can run in parallel

## The Problem

While the architecture is good, the implementation has excessive row updates because:
1. Each step updates the entire row for tracking
2. State transitions are tracked with individual updates
3. No batching of metadata updates

## Recommended Solutions

1. **Batch Metadata Updates**: Combine priority and state updates into single UPDATE
2. **In-Memory State Tracking**: Track progress in memory, update DB less frequently
3. **Columnar Updates**: Update only changed columns, not entire row
4. **Separate Progress Table**: Track import progress separately from data

## Statistical Variables - Not the Culprit

The statistical variables processing is actually well-designed:
- Uses efficient unpivot/pivot operations
- Handles multiple stat vars in one pass
- Only 2 stat vars exist (employees, turnover)
- Contributes just 1 of the 15 processing steps