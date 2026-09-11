# 4. Interview questions and spoken answers

## Architecture

### 1. Explain the project end to end.

Use the 60-second answer in `01_ARCHITECTURE_AND_FLOW.md`, then expand one layer
at a time: ingestion, validation, curated storage, governance, orchestration and
serving.

### 2. Why is it a lakehouse?

It keeps scalable object storage and open columnar files in S3, but adds table
metadata, ACID transactions, schema evolution and MERGE through Iceberg, plus
warehouse-style SQL consumption.

### 3. Why medallion layers?

They separate replayable source data from validated reusable data and
business-facing models. A problem in a gold/mart model does not require
re-extracting the source because curated data can be reused.

### 4. Is Redshift the storage layer?

The lakehouse storage is S3. Spectrum queries external S3 data without loading
it. The final dbt fact/dimension tables are physically stored inside Redshift,
so Redshift is the downstream serving warehouse.

## Glue and Spark

### 5. What is AWS Glue?

A managed data-integration service. In this project Glue provides managed Spark
jobs, a JDBC connection and the central Data Catalog integration.

### 6. What is a Glue job versus Glue Data Catalog?

A job is compute and transformation logic. The Catalog is metadata describing
databases, tables, columns, partitions and S3 locations.

### 7. Does a Catalog table store the actual data?

No. It stores metadata and a pointer to S3. Iceberg also stores metadata files,
manifests and snapshots in S3; the catalog points to the current table metadata.

### 8. Why DataFrame instead of only DynamicFrame?

DynamicFrames help with semi-structured and evolving schemas. DataFrames expose
the full Spark API and are clearer for casts, windows, joins, filters and SQL.

### 9. What is the grain of each transform?

Relational curated tables preserve the source table grain. `ratings` keeps one
current rating per customer-product pair. `ratings_for_ml` keeps rating events
with joined product context.

### 10. How do you handle schema drift?

Landing preserves source data. Curated code explicitly casts required columns;
missing/breaking changes fail or route invalid rows. Compatible additions can be
added to the schema and Iceberg supports schema evolution without rewriting all
historical files.

## Validation and data quality

### 11. Which validations are applied?

Non-null business keys, valid casts, positive quantities, non-negative monetary
values/stock, ratings 1-5, duplicate-key removal and customer/product referential
checks. Post-write checks verify PKs, ranges and orphans.

### 12. What is a business rule versus technical validation?

Technical validation checks whether data can be parsed and conforms to schema.
A business rule checks domain meaning, such as rating 1-5 or order quantity > 0.

### 13. Why not fail the whole job for every bad row?

Expected data-quality exceptions should be quarantined with reasons so valid
records can continue. Infrastructure errors or critical dataset-level failures
must fail the job to prevent untrusted downstream data.

### 14. How do you reconcile data?

Compare source count with valid plus rejected counts, then verify target keys and
aggregate totals. For joins/merges, compare business-key coverage and inserted or
updated records, not only total row count.

## Iceberg

### 15. Why Iceberg instead of plain Parquet?

Parquet is a file format. Iceberg is a table format over files that adds
snapshots, atomic commits, schema/partition evolution, MERGE, time travel and
metadata-based file pruning.

### 16. What is an Iceberg snapshot?

A consistent table version pointing through metadata and manifest files to a
set of data/delete files. Readers see one committed snapshot rather than a
partially written table.

### 17. How does MERGE help reruns?

It matches deterministic business keys and updates/inserts as required, so the
same input does not blindly append duplicate records.

### 18. What is a small-file problem?

Many tiny files increase listing, metadata and task overhead and reduce scan
efficiency. Solve it by controlling output partitions and periodically
compacting Iceberg data files.

## Lake Formation and IAM

### 19. IAM versus Lake Formation?

IAM controls AWS API access and role assumption. Lake Formation controls
fine-grained access to governed catalog databases, tables, columns/rows and
underlying data locations.

### 20. What is data-location access?

Permission allowing a principal to create/access Lake Formation catalog
resources backed by a registered S3 location. It does not replace every S3/IAM
permission.

### 21. How is least privilege shown?

Glue receives only pipeline service/data permissions. The ML user can describe
the presentation database and select only `ratings_for_ml`, with a restricted
Athena results path.

## Airflow and Docker

### 22. Why Airflow if Glue can schedule jobs?

Airflow manages cross-service dependencies, parallel branches, retries,
parameters, backfills and visibility across Glue, Athena and dbt. Glue remains
the transformation engine.

### 23. What is a DAG?

A directed acyclic graph of tasks and dependencies. A task starts only when its
upstream conditions are satisfied; cycles are not allowed.

### 24. How do retries work?

Transient task failures retry with delay. Deterministic bad data should not be
hidden by repeated retries; it should be rejected or fixed. Every retry must be
idempotent.

### 25. Why Docker?

It pins Airflow, provider and dbt dependencies, gives the same local environment
to every developer and avoids laptop-specific setup differences. Docker is the
runtime packaging, not the orchestration logic itself.

### 26. Is this Docker Compose production ready?

No. It is a local reproducible development environment. Production would use
managed Airflow or a highly available container platform with external metadata
DB, secrets, logging and worker scaling.

## dbt and dimensional modelling

### 27. What is dbt used for?

SQL transformations, dependency management, tests, documentation and lineage
inside Redshift. It starts after curated data is available through Spectrum.

### 28. What are fact and dimension tables?

Facts store measurable events at a declared grain. Dimensions store descriptive
attributes used to filter/group facts. Here the facts are order lines and
ratings; dimensions are customer, product and date.

### 29. What is a star schema?

A central fact table linked directly to denormalized dimensions. It simplifies
BI queries and produces consistent business definitions.

### 30. Why staging models?

They isolate source-specific names/types and provide a stable clean interface.
Marts depend on staging rather than repeatedly cleaning raw external columns.

### 31. What does `ref()` do?

It resolves the target relation and creates a dependency in dbt's DAG, ensuring
upstream models run before downstream models.

### 32. What does `source()` do?

It declares an external/raw relation with metadata and enables source lineage,
freshness and testing.

### 33. What is an incremental model?

A model that processes only new/changed records after the first build. This
project uses deterministic unique keys and merge materialization.

### 34. What if incremental logic is wrong?

It may silently miss updates or create duplicates. Validate watermark/keys,
compare against a full refresh and maintain a controlled backfill/full-refresh
procedure.

### 35. What are dbt tests?

SQL assertions. Generic tests cover unique, not-null, accepted values and
relationships; singular tests are custom SQL returning failing rows.

### 36. SCD Type 1 versus Type 2?

Type 1 overwrites the current dimension attribute. Type 2 adds a new version
with effective dates/current flag to preserve history. The current code uses
Type 1 merge; customer-history requirements would justify a Type 2 snapshot.

## Redshift and Spectrum

### 37. What is Redshift Spectrum?

A Redshift capability that queries external data in S3 using catalog metadata.
The external rows remain in S3.

### 38. External versus internal Redshift table?

External table metadata points to S3 and Spectrum scans it. Internal table data
is stored in Redshift-managed storage and is better for repeated serving and
warehouse optimizations.

### 39. Why materialize marts internally?

Repeated joins/aggregations become faster and more predictable, BI users get a
controlled semantic layer, and only high-value data consumes warehouse storage.

### 40. How would you tune Redshift?

Inspect query plans and workload, reduce scanned rows/columns, choose appropriate
sort/distribution strategy or allow automatic optimization, materialize repeated
logic, manage concurrency and vacuum/analyze where applicable.

## Audit, rejects and observability

### 41. Why DynamoDB for audit?

It supports simple low-latency status writes from distributed AWS jobs without
running a database server. The composite key gives one record per run and stage.

### 42. What is stored in rejected data?

Original business fields plus reject reason, run ID, processing date and
rejection timestamp. This makes the record explainable and replayable.

### 43. Audit table versus application logs?

Logs contain detailed execution events. The audit table contains structured
operational facts such as status and counts used for monitoring/reconciliation.
Both are required.

### 44. How do you alert?

Create CloudWatch alarms/EventBridge rules for Glue/DAG failures and data-quality
status, then notify SNS/Slack/on-call. The repository records the signals; an
enterprise deployment adds the notification integration.

## Rerun, backfill and failure handling

### 45. How do you rerun one date?

Trigger Airflow with the original processing date and a new run ID. Overwrite
that file partition, rerun validations, merge Iceberg/dbt keys and reconcile.

### 46. What is idempotency?

Repeating the same logical operation reaches the same final state rather than
producing additional side effects or duplicate rows.

### 47. What if Glue succeeds but Airflow loses the response?

The retry may attempt the stage again, so writes must be idempotent. Also search
Glue runs/audit by run ID before launching a duplicate in a stricter production
operator.

### 48. What if the target write succeeds but audit update fails?

The run appears uncertain. Reconcile target partition/table and Glue job status,
then repair the audit record. Do not blindly assume the business write failed.

### 49. What if dbt tests fail after models are built?

Block downstream publication/notification, inspect failing rows, fix source or
model logic and rerun the affected selection. For atomic release requirements,
build into a temporary schema and promote/swap only after tests pass.

## Scaling and design choices

### 50. How would you scale JDBC ingestion?

Use incremental predicates/bookmarks, partitioned JDBC reads, source indexes,
controlled parallelism and CDC for high-frequency change volumes.

### 51. How would you scale Spark?

Measure stage metrics, increase workers, repartition on useful keys, address skew,
avoid wide unnecessary shuffles, broadcast genuinely small dimensions and tune
output file sizes.

### 52. How would you scale orchestration?

Use Airflow pools/concurrency limits, separate DAGs by SLA/domain, deferrable
waiting and managed/HA Airflow infrastructure.

### 53. Why not put every transformation in dbt?

PySpark is better for file ingestion, schema enforcement, distributed row-level
processing and reject routing. dbt is best after data is queryable in a SQL
engine for analytics modelling and tests.

### 54. Why not load everything directly into Redshift?

S3 provides cheap durable replayable storage and decouples compute. Spectrum
queries broad curated data externally; only frequently used marts are loaded
internally.

### 55. What would you improve next?

Secrets Manager for all source credentials, automated alerts, CI checks,
Iceberg compaction/snapshot expiry, incremental JDBC/CDC, temporary-schema dbt
promotion, data contracts and production Airflow deployment.

## Honest questions

### 56. Did the original GitHub repository already contain Airflow/dbt/Redshift?

No. The public base contained Glue, S3, Catalog, Lake Formation, Athena,
Iceberg, Terraform and Python runners. This enhanced reconstruction adds the
missing orchestration, modelling, audit/reject and Redshift serving layers.

### 57. What part should you claim as production experience?

Only the Wipro production workflow you actually supported. Present this
lakehouse as a hands-on engineering project and distinguish reconstructed or
locally tested parts from production deployment.

## Additional implementation questions

### 58. Why did you not use a Glue crawler for every table?

The relational schemas and business keys are known, so the pipeline applies
explicit casts and updates the Catalog while writing. A crawler is useful for
initial discovery, but relying on inferred types in a controlled production
schema can silently change columns between runs.

### 59. What is a Glue bookmark, and are you using one here?

A bookmark stores source-processing state so supported Glue sources can resume
from previously processed data. The demo RDS ingestion is an explicit dated
snapshot and does not depend on bookmarks. At scale I would use a reliable
`updated_at` watermark, JDBC predicate, bookmark where appropriate, or CDC.

### 60. Why Parquet and Snappy?

Parquet is columnar, so Athena, Spectrum and Spark can read only required
columns and use statistics. Snappy gives fast compression/decompression and is
a common balance between storage reduction and CPU cost.

### 61. What is partition pruning?

When a query filters a partition column such as `processing_date`, the engine
can skip unrelated S3 partitions/files. It reduces bytes scanned, cost and
latency. Partitioning by a high-cardinality ID would create too many tiny
partitions and is usually a bad choice.

### 62. What is predicate pushdown?

The query engine pushes supported filters as close as possible to the external
scan so fewer rows move into later joins/aggregations. Columnar statistics and
Iceberg metadata help eliminate files before reading all records.

### 63. Why is `ratings_for_ml` event-level while `ratings` is current-state?

The event table preserves every valid rating event for history and model
training. The current table has one row per customer-product pair and is easier
for current recommendation/serving queries. Their grains and business purposes
are different.

### 64. How do you guarantee exactly-once processing?

I would not claim end-to-end exactly once across S3, Glue, DynamoDB, Athena and
Redshift because there is no single distributed transaction. The design is
at-least-once execution with idempotent outcomes: dated overwrites,
deterministic keys, deduplication and MERGE.

### 65. How are duplicate records handled?

Rows are ranked inside each batch by their business key. One deterministic row
continues and additional rows are written to the rejected zone with a duplicate
reason. This keeps count reconciliation visible instead of silently dropping
records.

### 66. How do you handle source deletes?

The current demo is snapshot/upsert oriented and does not propagate hard deletes
into every serving model. Production options are CDC delete events, a source
active flag, or snapshot reconciliation followed by controlled target deletes.
This limitation should be stated rather than hidden.

### 67. What happens if an old snapshot is backfilled after newer data exists?

Fact/event records are rebuilt for the requested date using deterministic keys.
Current Type-1 customer/product dimensions deliberately select the latest master
snapshot, so an old backfill does not regress current descriptive attributes.
For temporal dimension history I would implement SCD Type 2.

### 68. What are dbt materializations?

They define how a model is persisted: `view`, `table`, `incremental`, or
`ephemeral`. This project uses views for staging, incremental MERGE models for
facts and Type-1 dimensions, and tables for reporting marts.

### 69. Why use a custom `generate_schema_name` macro?

By default dbt may combine the target schema and custom schema, producing names
such as `analytics_staging`. The macro makes the intended physical schemas
exactly `staging` and `analytics`.

### 70. dbt incremental model versus dbt snapshot?

An incremental model controls how rows are added/updated in a target model. A
dbt snapshot tracks historical versions of mutable source rows using timestamps
or check columns and is suitable for SCD Type 2 history.

### 71. What is a Redshift namespace versus workgroup?

In Redshift Serverless, the namespace holds database/security/storage metadata;
the workgroup provides compute, network configuration and the endpoint used by
clients.

### 72. What are distribution and sort choices in Redshift?

Distribution controls where rows are stored across compute nodes and affects
data movement during joins. Sort order helps block pruning for common filters.
I would begin with automatic optimization, inspect real query plans and change
only when workload evidence supports it.

### 73. Can Spectrum update the external Parquet tables?

Spectrum is primarily the external query layer from Redshift. Curated writes are
owned by Glue/Iceberg jobs. dbt reads the external data and writes internal
Redshift models; ownership is deliberately separated.

### 74. Why `max_active_runs=1` in Airflow?

It prevents two DAG runs from refreshing the same Iceberg/presentation targets
at the same time, reducing commit conflicts and destructive refresh races.
Higher concurrency would require partition-isolated writes and stronger locking
or promotion logic.

### 75. What is Airflow catchup?

Catchup creates historical scheduled DAG runs between the start date and now.
It is disabled here to avoid accidental mass backfills; old dates are triggered
explicitly with a processing-date parameter.

### 76. What belongs in XCom?

Small orchestration metadata such as a Glue job-run ID or row-count summary—not
large datasets. Business data remains in S3/Redshift, because the Airflow
metadata database is not a data-transfer layer.

### 77. What is Terraform state?

State maps declared Terraform resources to real AWS objects and stores
attributes required to plan changes. It must be protected, remotely locked and
treated as sensitive because values can include infrastructure details.

### 78. Why Terraform modules?

Modules group related resources behind inputs and outputs, reduce repetition and
make dependencies visible. They should represent cohesive capabilities such as
storage, landing jobs, governance or Redshift—not one arbitrary module per file.

### 79. How should secrets be handled?

Do not commit RDS or Redshift passwords. Store them in Secrets Manager or a
secure CI secret store, grant retrieval to the runtime role, and mark Terraform
inputs sensitive. The example files contain placeholders only.

### 80. What is the strongest limitation of this demo?

The RDS path is a full snapshot rather than true incremental ingestion/CDC, and
local Docker Compose is not production Airflow. The architecture shows the
correct boundaries, rerun controls and serving model; production hardening would
add source watermarks/CDC, managed secrets, alerting, CI/CD and HA orchestration.
