FROM apache/airflow:2.10.5-python3.11

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER airflow

COPY requirements.txt /requirements.txt

RUN pip install --no-cache-dir \
    "apache-airflow==2.10.5" \
    -r /requirements.txt

RUN python -m venv /opt/airflow/dbt-venv && \
    /opt/airflow/dbt-venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/airflow/dbt-venv/bin/pip install --no-cache-dir \
        "dbt-core==1.10.11" \
        "dbt-athena==1.9.5"

ENV PATH="/opt/airflow/dbt-venv/bin:${PATH}"