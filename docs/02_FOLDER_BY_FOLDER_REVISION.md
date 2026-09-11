# 2. Folder-by-folder revision guide

Use this file while opening the matching folder.

## `terraform/`

Terraform is infrastructure as code. It declares the desired AWS resources,
compares them with Terraform state and asks AWS APIs to create or modify only
the difference.

### Root files

- `providers.tf`: pins Terraform/provider versions and configures the AWS
  provider and common tags.
- `variables.tf`: defines environment inputs. Definitions live here; actual
  values go into `terraform.tfvars`.
- `main.tf`: composes reusable modules and passes outputs from one module into
  another.
- `outputs.tf`: exposes useful names, ARNs and endpoints after apply.
- `terraform.tfvars.example`: safe template. Real passwords must not be
  committed.

### `modules/storage`

Creates the target S3 data-lake and Glue-script buckets with versioning,
encryption and public-access blocking.

Interview points:

- S3 is object storage, not a database.
- A prefix looks like a folder but is part of an object key.
- Versioning helps recover overwritten/deleted objects.
- Partitioning is a logical path/layout strategy, not a separate S3 resource.

### `modules/audit`

Creates a DynamoDB table with composite key `(run_id, stage)`.

Why DynamoDB:

- low-latency writes from Glue/Airflow
- no server management
- flexible metrics payload
- pay-per-request mode suits irregular pipeline runs
- point-in-time recovery protects operational history

### `modules/iam`

Creates the Glue execution role.

Know the distinction:

- Trust policy: who can assume the role (`glue.amazonaws.com`).
- Permission policy: what the assumed role may do (S3, Glue Catalog,
  Lake Formation and DynamoDB actions).
- IAM authenticates and authorizes AWS API calls. Lake Formation provides the
  data-lake permission layer over catalog/data resources.

### `modules/landing_etl`

Creates:

- Glue JDBC connection to RDS
- RDS ingestion Glue job
- ratings JSON ingestion Glue job
- uploads landing scripts to the scripts bucket

A Glue connection stores network/JDBC configuration used by a job. For a
private RDS source, Glue creates elastic network interfaces in the supplied
subnet and security groups.

### `modules/lakeformation`

Creates Glue Catalog databases, registers the S3 data-lake location and grants
Glue data-location/database permissions.

Registration tells Lake Formation which S3 location it governs. Data-location
access allows the principal to create/access tables backed by that location.
Database permissions control actions such as CREATE_TABLE, ALTER and DESCRIBE.

### `modules/transform_etl`

Uploads transformation scripts and creates four Glue jobs. Iceberg Spark
configuration is supplied through job arguments.

Important Glue terms:

- Glue job: managed Spark/Python execution definition.
- Worker type and number: compute size and parallelism.
- Job arguments: runtime parameters such as date, run ID and S3 paths.
- Glue Data Catalog: central technical metadata repository.
- DynamicFrame: Glue abstraction over Spark DataFrame with schema-handling
  helpers; code converts to DataFrame for normal PySpark logic.

### `modules/presentation`

Creates an Athena workgroup and named queries.

A workgroup isolates query history, result location, encryption, limits and
CloudWatch metrics. Athena reads data in S3; it does not load it into Athena
storage.

### `modules/redshift`

Optional because it can generate cost. It creates:

- Redshift Spectrum IAM role
- Redshift Serverless namespace
- Redshift Serverless workgroup

Namespace = database/storage/security boundary. Workgroup = compute and network
endpoint. Spectrum reads external S3 tables; dbt creates internal Redshift
marts.

### `modules/downstream_access`

Demonstrates least privilege. The ML user receives DESCRIBE on the presentation
database and SELECT only on `ratings_for_ml`, not landing/curated/all tables.

### `modules/event_trigger`

Optional alternative to scheduled Airflow ingestion. S3 events can reach SQS;
Lambda consumes SQS and starts the JSON Glue job. SQS buffers bursts and the DLQ
holds poison events. Do not run both event and scheduled modes for the same file
without an idempotency key.

## `terraform/assets/`

### `common/glue_utils.py`

Centralizes argument parsing and audit writes. Jobs write RUNNING, SUCCEEDED,
SUCCEEDED_WITH_REJECTS or FAILED with row counts/error text.

### `landing_etl_jobs/batch_ingress.py`

Loops through eight RDS tables, reads them through the Glue connection, adds
metadata and writes a date partition to landing S3.

### `landing_etl_jobs/json_ingress.py`

Reads source ratings JSON, adds technical metadata and writes the landing
partition.

### `transform_etl_jobs/batch_transform.py`

- casts source columns into expected types
- rejects null business keys
- rejects negative amounts/prices/stock and non-positive quantities
- removes duplicate primary keys within the batch
- writes rejected rows and reasons
- writes valid partitioned Parquet and updates the Glue Catalog

### `transform_etl_jobs/json_transform.py`

- casts rating fields
- validates rating range 1-5
- validates non-null customer/product keys
- checks that customer and product exist
- deduplicates repeated rating events
- joins product/customer context
- upserts `ratings_for_ml` as Iceberg

### `transform_etl_jobs/ratings_to_iceberg.py`

Uses a window to select the newest rating for each customer-product pair, then
uses Iceberg MERGE for idempotent upsert.

### `transform_etl_jobs/curated_quality_checks.py`

Runs dataset-level controls after all writes:

- primary-key null checks
- negative-value checks
- valid rating range
- orphan order-to-customer and orderdetail-to-product checks

Critical failures stop downstream presentation/dbt tasks.

## `airflow/`

Airflow orchestrates dependencies; it is not the transformation engine. The DAG
passes the same run ID and processing date to every job, waits for completion,
retries transient failures and only starts downstream tasks after upstream
success.

Docker provides a reproducible runtime containing Airflow, the AWS provider and
dbt. `docker-compose.yml` runs the scheduler, webserver and PostgreSQL metadata
database locally.

## `dbt/`

Dbt is SQL transformation and testing software. It does not ingest source files.
It compiles Jinja SQL, resolves model dependencies, executes SQL in Redshift,
and records tests/docs/lineage.

### Staging models

Views that rename/cast Spectrum external columns, scope fact processing to the
requested date and rank duplicate snapshot rows by business key. Customer and
product staging deliberately use the latest available master snapshot so an old
backfill cannot regress current Type-1 dimensions.

### Dimensions

Descriptive entities:

- customer
- product
- date

### Facts

Measurable events at an explicit grain:

- one row per order line
- one row per rating event

### Reporting marts

Business aggregates built from conformed facts/dimensions, not directly from
raw sources.

### dbt tests

- unique and not_null keys
- relationships between facts and dimensions
- accepted rating values
- singular test for positive quantity/amount

`dbt build` runs models and tests in dependency order. A failed critical test
causes the Airflow dbt task to fail.

## `presentation_sql/`

Athena statements create the presentation Iceberg tables when absent, then
DELETE and INSERT refreshed results. Because the DAG permits one active run,
these controlled full refreshes do not overlap. The Redshift/dbt layer remains
the main downstream star-schema serving path.

## `scripts/`

- `run_pipeline.py`: manual non-Airflow Glue runner.
- `run_presentation_queries.py`: renders and executes Athena SQL.
- `bootstrap_redshift.py`: creates Spectrum external schema plus staging and
  analytics schemas through the Redshift Data API.
