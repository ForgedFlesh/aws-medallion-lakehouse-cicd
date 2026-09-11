# 1. Architecture and complete runtime flow

## Your 60-second interview answer

I built a governed AWS medallion lakehouse for the Classic Models sales domain
and product ratings. MySQL/RDS tables and JSON ratings are ingested into an S3
landing zone by parameterized Glue jobs. PySpark validates schemas and business
rules, routes invalid records to an S3 rejected zone, and writes valid data as
partitioned Parquet and Iceberg tables in the curated zone. The Glue Data
Catalog stores table metadata, Lake Formation controls database and table
access, and DynamoDB stores run-level audit status and row counts. Airflow,
running in Docker, orchestrates ingestion, transformation, quality checks,
Athena presentation refresh and dbt. Redshift Spectrum exposes the curated S3
tables as external tables, while dbt builds internal Redshift fact and dimension
models for downstream analytics.

## Layer-by-layer design

### Source layer

- MySQL/RDS database: customers, products, orders, orderdetails, payments,
  employees, offices and productlines.
- Ratings JSON in a source S3 bucket: customer number, product code, rating and
  optional event timestamp.

### Landing layer

- Path pattern: `s3://bucket/landing_zone/<source>/<table>/processing_date=.../`
- Purpose: replayable source-aligned copy with minimal changes.
- Added metadata: ingest timestamp, source, processing date and run ID.
- Rerun strategy: overwrite only the requested processing-date partition.

### Curated layer

- Relational source tables become schema-enforced Snappy Parquet.
- Ratings and ratings-for-ML become Iceberg v2 tables.
- Invalid records go to `rejected_zone` with a reject reason.
- Dataset-level checks are written to `quality_results`.

### Metadata and governance

- Glue Data Catalog databases: `curated_zone` and `presentation_zone`.
- A catalog table stores logical columns, types, partitions, storage location
  and table-format metadata. It does not hold the business rows.
- Lake Formation registers the S3 data location and grants metadata/data
  permissions to Glue, Redshift and downstream users.

### Query and serving

- Athena creates business-facing Iceberg presentation tables.
- Redshift Spectrum creates an external schema over `curated_zone`.
- dbt reads the external Spectrum tables and materializes internal Redshift
  dimensions, facts and reporting marts.

## Exact execution order

1. Airflow records DAG status as RUNNING.
2. RDS ingestion and ratings JSON ingestion run in parallel.
3. Relational batch transform validates and publishes curated Parquet.
4. Ratings transform validates, joins customer/product masters and builds
   `ratings_for_ml`.
5. Ratings merge keeps the latest customer-product rating in Iceberg.
6. Curated quality checks validate keys, ranges and referential integrity.
7. Athena presentation Iceberg tables are refreshed deterministically.
8. If Redshift is enabled, dbt builds and tests the internal star schema; the
   task is safely skipped in the lower-cost lakehouse-only mode.
9. Airflow inspects upstream states and records the final DAG result.

## Why both Athena and Redshift?

Athena is serverless and useful for ad hoc S3 queries and lightweight
presentation-table creation. Redshift is the repeated BI-serving layer: it gives
workload management, cached/internal tables, joins over dimensional models and
predictable dashboards. Spectrum avoids copying every curated table into the
warehouse, while dbt selectively materializes the high-value marts.
