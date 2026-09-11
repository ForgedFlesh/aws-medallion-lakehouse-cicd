# 3. Failures, reruns, scaling and production defence

## Where can the pipeline fail?

### Terraform/provisioning

- global S3 bucket name collision
- insufficient IAM/Lake Formation administrator permissions
- Glue script object missing from scripts bucket
- invalid subnet/security group/AZ combination
- Redshift workgroup subnet capacity or endpoint issue

Response: inspect Terraform error, CloudTrail/API message and plan/state. Fix the
specific dependency; do not manually create competing resources without import.

### RDS ingestion

- Glue cannot reach RDS
- wrong JDBC URL/credentials
- source table/schema change
- connection exhaustion or long full-table scan

Response: check Glue job logs, ENI/subnet routes, security-group rules and JDBC
error. Use incremental predicates/bookmarks for large tables rather than daily
full extracts.

### JSON ingestion

- wrong S3 prefix
- malformed JSON or schema drift
- duplicate event notification
- object arrives partially/in multiple files

Response: keep raw object immutable, use object key/ETag as idempotency input,
quarantine malformed files and replay after correction.

### Transformation

- cast failures
- missing key columns
- unexpected source values
- data skew or executor out-of-memory
- too many small files
- Iceberg commit conflict

Response: separate bad records from infrastructure failures. Bad rows go to the
rejected zone; Spark/AWS failures fail the job. Tune workers/partitions, compact
small files and serialize conflicting writes per table.

### Catalog/Lake Formation

- table exists in S3 but not Catalog
- IAM allows S3 but Lake Formation denies metadata/data access
- wrong database/table name or case
- registered location does not cover the actual S3 prefix

Response: verify catalog table location/schema, Lake Formation grants,
`GetDataAccess`, data-location registration and principal ARN.

### Athena

- curated dependency does not exist
- CTAS target location already contains conflicting data
- workgroup result path permission denied
- incompatible column types

Response: query the curated table first, inspect failure reason, clean only the
failed CTAS output path and rerun the presentation stage.

### Redshift Spectrum/dbt

- external schema not bootstrapped
- Redshift IAM role lacks Glue/S3/Lake Formation permission
- dbt profile/credential issue
- dbt test failure
- incremental unique key is wrong, causing duplicate or incorrect merge

Response: test a direct Spectrum SELECT, then `dbt debug`, `dbt compile`, model
run and tests separately. Never ignore a failed data-quality test to make the DAG
green.

## Rerun and backfill design

A rerun receives the same logical `processing_date` but a new operational
`run_id`.

- Landing writes overwrite only that date partition.
- Curated Parquet writes update only that partition.
- Iceberg uses deterministic keys and MERGE.
- dbt incremental models use unique keys and merge; staging rows are unique per
  source business key.
- Audit records remain separate because run ID differs.
- Rejected rows are stored under both date and run ID.

Backfill procedure:

1. Trigger the DAG with an old processing date and `run_mode=backfill`.
2. Rebuild that landing partition from the raw/source data.
3. Re-run transformations and quality checks.
4. MERGE corrected records into Iceberg.
5. Run dbt with the affected date range or full refresh if model logic changed.
6. Reconcile source count, valid count, rejected count and target count.

## Idempotency answer

Idempotency means rerunning the same logical input produces the same final
business state rather than duplicates. This project achieves it through
partition overwrite for file layers, primary-key deduplication, Iceberg MERGE,
dbt merge with unique keys and one active Airflow run.

## Scaling

### More source rows

- replace full JDBC scans with incremental predicates or Glue bookmarks
- partition JDBC reads using lower/upper bounds and a numeric key
- increase Glue workers only after inspecting stage metrics
- avoid collecting large data to the driver

### More S3 data

- partition by frequently filtered, reasonably sized columns such as processing
  date; avoid high-cardinality keys
- write Parquet with compression
- target healthy file sizes instead of thousands of tiny files
- compact Iceberg files and expire old snapshots under retention policy
- use partition pruning and column projection

### More Airflow workflows

- use pools to cap concurrent Glue/Redshift jobs
- separate ingestion and serving DAGs if independent SLAs emerge
- use deferrable sensors/operators where supported to avoid occupied workers
- move Airflow from local Docker to MWAA/ECS/Kubernetes for production HA

### More Redshift users

- materialize repeated heavy joins into marts
- choose distribution/sort strategy based on join/filter patterns
- use auto workload management and query monitoring
- isolate BI and transformation workloads
- keep cold/detail data external and hot aggregates internal

## Cost controls

- Redshift is disabled by default
- right-size Glue workers and enable auto scaling where appropriate
- partition/prune Athena and Spectrum scans
- compress Parquet
- avoid unnecessary daily full refreshes
- apply S3 lifecycle policies only after defining replay/retention requirements
- set CloudWatch/AWS Budget alarms

## Monitoring and reconciliation

For each stage record:

- run ID and processing date
- start/end/status
- source row count
- valid/rejected count
- target row count
- Glue job-run ID or query ID
- error message

A core reconciliation is:

`source_count = valid_count + rejected_count`

For merge targets, also verify inserted/updated counts or compare business keys,
not only total table count.

## Known boundary: snapshot deletes and temporal state

The demo RDS job extracts full snapshots. Upserts are idempotent, but a row that
disappears from the source is not automatically deleted from every downstream
table. A production implementation must choose a contract: CDC tombstones, an
`is_deleted` flag, or snapshot anti-join reconciliation. Similarly, backfilling
an old snapshot must not overwrite a newer Type-1 dimension; the dbt customer
and product staging models therefore select the latest master partition.
