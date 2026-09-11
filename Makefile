.PHONY: help airflow-up airflow-down dbt-build python-check zip

help:
	@echo "airflow-up     Start local Airflow"
	@echo "airflow-down   Stop local Airflow"
	@echo "dbt-build      Run dbt build inside Airflow container"
	@echo "python-check   Compile all Python files"
	@echo "zip            Create a distributable archive"

airflow-up:
	docker compose up airflow-init
	docker compose up -d

airflow-down:
	docker compose down

dbt-build:
	docker compose exec airflow-scheduler bash -lc "cd /opt/airflow/dbt && dbt build"

python-check:
	python -m compileall airflow scripts terraform/assets

zip:
	cd .. && zip -r medallion-lakehouse-interview-ready.zip medallion-lakehouse-interview-ready \
		-x "*/.terraform/*" "*/target/*" "*/logs/*" "*/__pycache__/*"
