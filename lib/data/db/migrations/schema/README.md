# Schema snapshots

Drift's step-by-step migrations are generated from **committed snapshots** of each schema
version. Without a snapshot for v1 there is no starting point, so a v1 → v2 migration becomes
impossible to generate later — and unlike most mistakes in this project, that one is not
recoverable after users have data. ARCH_2 §13 calls this a five-minute task; it is, and it has to
happen now rather than when v2 is needed.

## 1. Dump the current schema — do this now, at v1

```bash
dart run drift_dev schema dump lib/data/db/alaya_database.dart drift_schemas/