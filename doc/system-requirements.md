# System Requirements

This document helps IT administrators provision hardware for on-premise StatBus deployments (VMware, Hyper-V, or bare metal). All values are **minimums** — more resources are always beneficial and recommended when budget allows.

StatBus development is funded by NORAD (Norwegian Agency for Development Cooperation). Current and prospective deployments include statistics offices across Africa (Ghana, Ethiopia, Kenya, Uganda, Morocco), Asia (Mongolia, Laos), and European accession countries (Albania, Northern Cyprus, Ukraine). We hope Norway's own statistics office will also adopt StatBus in the future.

## Quick Reference

Size your deployment based on the total number of legal units in your register:

| Size | Legal Units | Example Countries | Disk (min) | RAM (min) | CPU (min) |
|------|-------------|-------------------|------------|-----------|-----------|
| S | < 50K | Laos, Mongolia, Northern Cyprus | 20 GB | 4 GB | 2 cores |
| M | 50K – 500K | Albania, Ghana, Kenya, Uganda, Ethiopia, Morocco | 50 GB | 8 GB | 4 cores |
| L | 500K – 2M | Nigeria, South Africa, Egypt; Norway (aspirational) | 120 GB | 16 GB | 4 cores |
| XL | 2M – 5M | Large economies if they adopt StatBus | 250 GB | 32 GB | 4 cores |

**All sizes are floors.** More disk provides room for longer backup retention and import history. More RAM means faster search responses. More CPU cores speed up initial imports (PostgreSQL uses parallel query). There is no upper limit where more resources become wasteful.

**CPU note:** 4 cores is recommended for all sizes. PostgreSQL's parallel query and the 4 concurrent analytics backends benefit from 4 cores. More cores (8+) help during initial imports of very large registries but are not required — the system remains fully functional on 4 cores at any scale, just with longer import times. VMs are typically provisioned in powers of 2 (2, 4, 8 cores), so 4 is the practical sweet spot.

**Disk includes:** OS (~5 GB), Docker images (~3 GB), PostgreSQL WAL and temp space (~10–20%), import job retention (upload and data tables persist up to 18 months), local database backups, and 40% free headroom for VACUUM, reindex, and growth.

## Sizing Formula

Derived from the full Norwegian Business Register (BRREG) import: 1.96M legal units producing 18 GB of data.

### Per Legal Unit Storage

Each legal unit — including all related entities, derived tables, and indexes — requires:

| Component | Per LU | Notes |
|-----------|--------|-------|
| Base tables (LU + ES + enterprise + activity + location + ext_ident + contact + stats) | ~3.1 KB | Includes indexes |
| Derived tables (statistical_unit, timelines, timepoints, timesegments, facets, history) | ~8.5 KB | Search page indexes account for most of this |
| Import overhead (temporary, during initial load) | ~2.0 KB | Upload + data tables; reclaimable after import |
| **Total per LU** | **~13.6 KB** | **~13 GB per million legal units** |

Raw data formula:

    Data (GB) = (legal_units / 1,000,000) x 13

### Recommended Disk Provisioning

The recommended disk size accounts for:

- **OS and system packages:** ~5 GB
- **PostgreSQL WAL and temp space:** ~15% of data size
- **Import job retention:** upload and data tables persist for 18 months (~2 KB/LU per active import)
- **Local backup snapshots:** at least 1x data size (recommend `pg_dump` on schedule)
- **VACUUM overhead:** needs ~20% free for table maintenance
- **Growth headroom:** ~20% for new imports and temporal history accumulation

Formula:

    Recommended Disk (GB) = Data x 3 + 10

This means roughly **40 GB per million legal units** as a minimum, including all overheads:

- 1M LU -> 50 GB minimum (more is better for backup retention)
- 500K LU -> 30 GB minimum
- 50K LU -> 20 GB minimum (OS + Docker images set this floor regardless of data size)

### Establishment Multiplier

Norway has 0.73 establishments per legal unit. Countries with more multi-establishment enterprises will need proportionally more storage. The formulas above already include establishments at the Norwegian ratio.

### Informal Sector and Census Data

StatBus's temporal model supports loading entire census datasets for fixed time periods (e.g., informal sector census 2015–2020). Establishments from these censuses exist only within their census period and don't require change tracking across censuses — but they still contribute to graphs, aggregations, and the search index.

In developing economies with large informal sectors, the number of establishments from censuses can far exceed formal legal units. For example, a country with 200K formal legal units might load 2M informal establishments from a census.

**Size the system based on total units across all time periods**, not just current formal registrations.

## Estimating Your Country's Unit Count

If your country doesn't yet have a register, estimate the number of legal units from population:

| Economy type | LU per 1,000 population | Examples |
|--------------|------------------------|----------|
| Developed (Nordic, EU) | 70–200 | Norway, EU member states |
| Middle-income | 30–80 | Morocco, Albania, Ukraine |
| Developing (formal sector only) | 10–40 | Ghana, Ethiopia, Uganda, Mongolia, Laos |

**Important:** These ratios cover formal legal units only. Countries with large informal sectors may also load census data covering informal establishments — potentially 5–10x the formal count. When sizing, estimate the **total units across all sources and time periods**.

### Reference Points from Public Data

| Country | Legal Units | Population | LU per 1,000 | Notes |
|---------|-------------|------------|---------------|-------|
| Norway | 1.13M | 5.5M | 206 | Provides our empirical sizing baseline |
| EU average | ~33M | 450M | ~73 | Across all member states |
| South Africa | ~2M | 60M | ~33 | Estimated formal businesses |
| Kenya | ~1.5M | 55M | ~27 | Estimated registered businesses |
| Ghana | ~500K | 34M | ~15 | Estimated registered businesses |
| Ethiopia | ~200K | 126M | ~2 | Formal only; informal census data could add millions |

## Memory Requirements

RAM is consumed by:

- **OS + Docker overhead:** ~1 GB
- **PostgreSQL shared_buffers:** 25% of total RAM (main query cache)
- **PostgreSQL work_mem per backend:** default 4 MB x concurrent backends (up to ~5 during analytics)
- **OS page cache:** remaining RAM serves as secondary disk cache — this is where "warm" indexes live
- **Other containers:** worker (~50 MB), PostgREST (~100 MB), Next.js (~200 MB), Caddy (~30 MB) = ~400 MB total

### Why RAM Matters for Search

The search page's responsiveness depends on index caching. At Norway scale, `statistical_unit` has 3.9 GB of indexes. If these fit in shared_buffers + OS page cache, search is fast (~50 ms). If they spill to disk, search degrades to ~500 ms+ (still functional, but noticeably slower).

### RAM Sizing Formula

    RAM (GB) = max(4, data_size_GB x 0.5)

- **4 GB minimum:** enough for small registries where all indexes fit in RAM
- **8 GB:** covers medium registries; most hot indexes cached
- **16 GB:** covers Norway-scale; all search indexes fit in memory
- **32 GB:** large registries with headroom for concurrent analytics + queries

## CPU and Container Architecture

StatBus runs 5 Docker containers, but nearly all computation happens inside PostgreSQL:

| Container | Image Size | CPU Profile | RAM Profile |
|-----------|-----------|-------------|-------------|
| **db** (PostgreSQL 18) | 1.65 GB | Heavy — all query processing, analytics, imports | Dominant — shared_buffers + OS cache |
| **worker** (Crystal CLI) | 28 MB | Minimal — orchestrator only, dispatches SQL calls | ~50 MB |
| **rest** (PostgREST) | 613 MB | Light — HTTP-to-SQL translation | ~100 MB |
| **app** (Next.js) | 370 MB | Light — SSR minimal, mostly client-side rendering | ~200 MB |
| **proxy** (Caddy) | 127 MB | Negligible — reverse proxy + TLS | ~30 MB |

Docker images total: ~2.8 GB on disk.

The worker doesn't use separate threads — it dispatches tasks to PostgreSQL, which processes them as database backends. The analytics queue runs up to 4 concurrent PostgreSQL backends. During import, PostgreSQL is the bottleneck (I/O-bound for bulk inserts, CPU-bound for index maintenance).

### CPU Recommendation

- **2 cores:** functional minimum for small registries; import will be slow but the system works
- **4 cores:** recommended for all sizes — PostgreSQL uses parallel query and the 4 concurrent analytics backends benefit from it. This is the practical sweet spot for VM provisioning (VMs are typically allocated in powers of 2)
- **8+ cores:** beneficial for large registries (2M+ LU) where import speed matters, or when concurrent imports and user queries should not compete. Not required — 4 cores handles any registry size, just with longer imports

The jump from 4 to 8 is where diminishing returns set in. 4 cores is the right floor for any production deployment.

## Import Duration Estimates

Based on Norway (1.96M units processed in 5h 23min wall clock on 4 cores):

- Import processing: ~6.8 ms per row (includes parsing, validation, upsert)
- Derivation pipeline: ~14.3 ms per statistical_unit row

Formula:

    Hours = legal_units x 0.01 / 3600

Roughly **3 hours per million legal units** for a full initial import.

| Legal Units | Estimated Import Time |
|-------------|----------------------|
| 50K | ~10 minutes |
| 200K | ~35 minutes |
| 500K | ~1.5 hours |
| 1M | ~3 hours |
| 2M | ~6 hours |

Update imports (monthly/yearly) are much faster — only changed rows are processed, and the derived pipeline is incremental.

## Disk I/O Considerations

- **SSD:** strongly recommended (indexes rely on random reads)
- **HDD:** functional but search response times will be 5–10x slower
- **NVMe:** diminishing returns vs SATA SSD for this workload

SSD is the single most impactful hardware choice after having sufficient RAM. If budget is constrained, prioritize SSD over extra RAM or CPU.

## Network Requirements

- **Outbound HTTPS (port 443):** required during setup for Docker image pulls and package updates
- **Inbound HTTPS (port 443):** required for user access (Caddy handles TLS termination)
- **Inbound PostgreSQL (port 5432):** optional, only if external tools need direct database access
- **Bandwidth:** minimal for normal operation; the web interface transfers small JSON payloads. Initial Docker image pull requires ~3 GB download.

## Operating System

StatBus is tested on Ubuntu LTS 24.04. Any Linux distribution with Docker Engine 24+ and Docker Compose v2 will work. See `doc/harden-ubuntu-lts-24.md` for security hardening guidance.

Windows Server with Docker (WSL2 or Hyper-V backend) is not tested but should work. Linux is recommended for production.
