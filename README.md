# AWS Governed Medallion Lakehouse 🚀

> This project taught me what months of theory couldn't — how data actually flows between AWS services, how those services communicate securely, and how to make sure downstream consumers receive trustworthy data.

An end-to-end AWS Data Engineering project built from the ground up — **networking, ingestion, transformation, governance, orchestration, Infrastructure as Code, testing and CI/CD**.

The idea behind the pipeline is simple:

> **No data is better than corrupted data.**

---

## Architecture

```text
RDS MySQL + Ratings JSON (S3)
              ↓
        AWS Glue Ingestion
              ↓
          Landing Zone
              ↓
      Glue Transformation
              ↓
     Validation / Casting
        ↙           ↘
 Rejected Data    Curated Data
                   │
          Parquet + Iceberg
                   ↓
          Glue Data Catalog
                   ↓
          Lake Formation
           Governance Layer
                   ↓
               Athena
                   ↓
         Presentation Zone
                   ↓
             dbt-athena
                   ↓
       Dimensional / BI Models
```

**Apache Airflow** orchestrates the complete pipeline, while **DynamoDB** maintains pipeline audit information, statuses and record counts.

---

## What the Pipeline Does

- Ingests **8 tables from RDS MySQL** running inside private subnets.
- Ingests changing customer-rating JSON files from S3.
- Enforces schemas, casts datatypes and validates incoming records.
- Separates **valid and rejected data** instead of allowing corrupted records downstream.
- Stores stable relational data as **Snappy Parquet**.
- Uses **Apache Iceberg** for changing datasets and incremental processing.
- Registers metadata in the **AWS Glue Data Catalog**.
- Runs curated-layer **data-quality checks** before publishing data.
- Uses **Athena Engine v3** for serverless querying.
- Builds presentation-layer and dimensional models using **dbt-athena**.
- Tracks pipeline execution and audit information in **DynamoDB**.

---

## Governance & Security

The data lake is governed using **AWS Lake Formation**.

IAM controls whether an identity can call AWS services, while Lake Formation provides fine-grained permissions over governed databases, tables and data locations.

This allows permissions such as:

```text
SELECT
DESCRIBE
DATA_LOCATION_ACCESS
```

to be granted only to the required downstream identities.

---

## Infrastructure & Orchestration

The complete AWS infrastructure is managed using **Terraform**, including:

```text
VPC / Private Subnets / Security Groups
RDS
S3
Glue
DynamoDB
IAM
Lake Formation
Athena
```

Airflow currently runs through Docker and orchestrates:

```text
RDS + JSON Ingestion
        ↓
Transformation
        ↓
Iceberg MERGE
        ↓
Data Quality
        ↓
Athena Presentation
        ↓
dbt Build
```

---

## DEV / PROD & CI/CD

The same Terraform code is reused with isolated environment configuration:

```text
dev.tfvars  → DEV resources
prod.tfvars → PROD resources
```

Terraform state is stored remotely in S3 with separate DEV and PROD state.

GitHub Actions provides CI/CD:

```text
Feature Branch
      ↓
Pull Request
      ↓
Python + Terraform + Docker CI
      ↓
Protected Main Branch
      ↓
Merge
      ↓
GitHub Actions DEV Deployment
      ↓
OIDC → AWS IAM Role
      ↓
Terraform Plan + Apply
      ↓
DEV Environment
```

GitHub authenticates to AWS using **OIDC and temporary STS credentials**, so long-lived AWS access keys are not stored in the repository.

The next promotion stage is:

```text
DEV Smoke / Integration Tests
            ↓
      Manual Approval
            ↓
       PROD Deployment
```

---

## Tech Stack

**AWS:** S3, RDS MySQL, Glue, Athena, Lake Formation, DynamoDB, IAM, VPC  
**Data:** Parquet, Apache Iceberg  
**Processing:** Python, PySpark, SQL  
**Analytics:** dbt-athena  
**Orchestration:** Apache Airflow  
**Infrastructure:** Terraform  
**Containers:** Docker  
**Testing:** pytest, dbt tests, Terraform validation  
**CI/CD:** GitHub Actions + GitHub OIDC

---

## Goal

This project is not only about moving data from one place to another.

It demonstrates how to build a pipeline where **bad data is isolated, good data is governed, processing is auditable, infrastructure is reproducible and deployments are automated**.