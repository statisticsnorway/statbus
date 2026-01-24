# STATBUS Import Performance Optimization Plan

## **Current Situation Analysis**

✅ **Root Cause Identified**: The analysis in `tmp/32_updates_analysis.md` correctly identifies that the 32+ updates per row are caused by **15 processing steps**, each performing **2-3 priority/state updates per row**, NOT statistical variables.

✅ **Architecture Understanding**: The step-based processing (external_idents → legal_unit → locations → activities → statistical_variables, etc.) is actually well-designed for modularity and error recovery.

✅ **Performance Context**: Currently processing ~150 rows/sec, with 32 updates per row, targeting 500+ rows/sec.

## **Optimization Strategy**

### **Phase 1: Reduce Database Updates (Primary Bottleneck)**
**Target**: Reduce from 32+ updates to <10 updates per row

#### **1A. Batch Metadata Updates**
- **Current**: Each step does separate `UPDATE ... SET last_completed_priority = N` and `UPDATE ... SET state = 'processing'`
- **Optimization**: Combine into single UPDATE per step: `UPDATE ... SET last_completed_priority = N, state = 'processing'`
- **Impact**: Reduce from 38 updates to ~15 updates per row (60% reduction)

#### **1B. Progress Tracking Redesign** 
**Option A - In-Memory Progress (Recommended)**:
- Track step progress in procedure variables
- Update database only at key checkpoints (start, errors, completion)
- Batch state updates across multiple rows

**Option B - Separate Progress Table**:
- Move step tracking to dedicated `import_job_progress` table
- Keep main data table focused on data, not metadata
- Reduces row locking contention

#### **1C. Columnar Updates**
- Update only changed columns rather than touching entire row
- Use more targeted UPDATE statements
- Leverage PostgreSQL's HEAP optimization for unchanged columns

### **Phase 2: Leverage Existing Optimizations**
**Target**: Apply proven hot-patch improvements

#### **2A. Apply Hot-Patch Files**
You have 5 proven optimization files in `tmp/`:
- `hotpatch_fundamental_algorithm_improvement.sql`
- `hotpatch_memory_and_join_optimization.sql` 
- `hotpatch_processing_batch_optimization.sql`
- `hotpatch_batch_selection_optimization.sql`
- `hotpatch_final_memory_boost.sql`

**Action**: Review and integrate these optimizations that have already been developed and tested.

### **Phase 3: Set-Based Processing Enhancement**
**Target**: Maximize use of sql_saga temporal_merge patterns

#### **3A. Batch Size Optimization**
- **Current**: Uses range-based batching per step
- **Optimization**: Align with sql_saga's optimal 1000-row batches
- **Method**: Use `int4multirange` more effectively for set operations

#### **3B. Statistical Variables Optimization** 
- **Current**: Well-designed unpivot/pivot operations
- **Enhancement**: Pre-aggregate statistical definitions to reduce lookup overhead
- **Note**: This step is already efficient - only contributes 1 of 15 processing steps

### **Phase 4: Memory and Query Optimization**
**Target**: Reduce query planning and execution overhead

#### **4A. Connection and Memory Settings**
- **Current**: work_mem=1GB, hash_mem_multiplier=8x applied
- **Enhancement**: Tune for specific import workload patterns
- **Monitor**: Use auto_explain logging (DEBUG=true) for query optimization

#### **4B. Index Strategy**
- Ensure optimal indexes for range-based row_id queries
- Consider covering indexes for priority/state updates
- Evaluate partial indexes for active import states

## **Implementation Approach**

### **Development Methodology**
1. **Empirical Testing**: Use DEBUG=true logging to measure actual impact
2. **Incremental Changes**: Apply one optimization category at a time
3. **Performance Benchmarking**: Test with selection dataset (~24K rows) then full dataset
4. **Evidence-Based**: Each change must show measurable improvement

### **Testing Framework**
```bash
# Baseline measurement
./devops/manage-statbus.sh recreate-database
time USER_EMAIL=jorgen@veridit.no ./samples/norway/brreg/brreg-import-selection.sh

# Monitor with logging
docker compose logs db -f | grep -A 5 "duration.*ms.*plan"

# Measure updates per row  
echo "SELECT sql_statement, count(*) FROM import_update_log GROUP BY sql_statement;" | ./devops/manage-statbus.sh psql
```

## **Questions for You**

1. **Priority Preference**: Would you prefer to start with **Phase 1 (reduce updates)** for maximum impact, or **Phase 2 (apply existing hot-patches)** to build on proven work?

2. **Risk Tolerance**: Are you comfortable with **architectural changes** (separate progress table), or prefer **implementation optimizations** (batch updates, in-memory tracking)?

3. **Testing Scope**: Should we optimize for the **selection dataset** (24K rows, fast iteration) or jump to **full dataset** (1.1M rows, realistic load)?

4. **Monitoring Preference**: Do you want **detailed performance instrumentation** during optimization, or focus on **end-to-end timing** measurements?

## **Expected Outcomes**

### **Conservative Estimates**
- **Phase 1**: 60% reduction in updates → 2x performance improvement → **300 rows/sec**
- **Phase 2**: Hot-patch integration → 20-30% additional improvement → **375-400 rows/sec**  
- **Phase 3**: Set-based optimization → 15-25% improvement → **450-500 rows/sec**

### **Optimistic Targets**
- Combined optimizations could achieve **500-750 rows/sec**
- Reduced database load enables better concurrency
- More predictable performance across different data sizes

The analysis work has been excellent - now we have a clear, evidence-based path forward. What's your preference for where to start?

## **Implementation Status**
- **Created**: 2026-01-24
- **Status**: Ready for implementation
- **Next Action**: Await user preference on starting phase