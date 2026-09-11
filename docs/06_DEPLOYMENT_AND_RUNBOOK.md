# 6. Deployment and runbook

## Prerequisites

- AWS account and configured CLI credentials
- Terraform 1.6+
- Python 3.11+
- Docker Desktop
- existing MySQL/RDS Classic Models database
- existing source S3 bucket containing ratings JSON
- VPC network path from Glue to RDS

## Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Review the plan carefully. Redshift is disabled by default. The restricted ML
user is also disabled initially because its table-level Lake Formation grant
references `presentation_zone.ratings_for_ml`, which is created by the runtime
pipeline rather than the first Terraform apply. Enable downstream access and
apply again only after that table exists.

## Redshift bootstrap

After enabling Redshift, use Terraform outputs:

```bash
python scripts/bootstrap_redshift.py \
  --region us-east-1 \
  --workgroup medallion-lakehouse \
  --database lakehouse \
  --curated-database curated_zone \
  --iam-role-arn <redshift-spectrum-role-arn>
```

## Airflow

```bash
cp airflow/.env.example airflow/.env
cp dbt/profiles.yml.example dbt/profiles.yml
# Set ENABLE_REDSHIFT=true only after Redshift bootstrap succeeds.
docker compose up airflow-init
docker compose up -d
```

Open `http://localhost:8080`, enable the DAG and trigger it with a processing
date. With `ENABLE_REDSHIFT=false`, the lakehouse/Athena path still runs and the
dbt task exits successfully without attempting a Redshift connection.

## Manual Glue run

```bash
python scripts/run_pipeline.py \
  --aws-region us-east-1 \
  --data-lake-bucket-name <bucket> \
  --processing-date 2026-07-27 \
  --run-id manual-20260727-01
```

## Validation checklist

- landing date partitions exist
- curated Catalog tables are queryable
- rejected count is understood
- audit records exist for every stage
- quality result file says PASSED
- Athena presentation queries succeed
- Spectrum can select external tables
- `dbt build` passes
- fact/dimension row counts reconcile

## Destruction

Do not casually run `terraform destroy` against a data lake. The buckets use
`force_destroy=false`; preserve required data and understand retention before
removing infrastructure.
