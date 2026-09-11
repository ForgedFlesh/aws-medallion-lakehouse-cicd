# Source and reconstruction notes

The public base repository used for this reconstruction was:

`https://github.com/gamebred17/medallion-lakehouse-with-aws-lake-formation`

The base repository exposed this structure and design:

- `presentation_sql/`
- `scripts/run_pipeline.py`
- `scripts/run_presentation_queries.py`
- Terraform modules for IAM, landing ETL, transform ETL, Lake Formation,
  presentation and downstream access
- landing scripts `batch_ingress.py` and `json_ingress.py`
- transform scripts `batch_transform.py`, `json_transform.py` and
  `ratings_to_iceberg.py`
- RDS and ratings JSON sources, curated Parquet/Iceberg and Athena tables

Because the base archive could not be cloned in this execution environment,
this package is a clean-room reconstruction guided by the public repository
layout/README and the user's prior project description. It is not a byte-for-
byte copy. Airflow, dbt, Redshift, audit, reject, quality and event-trigger code
are enhanced additions.
