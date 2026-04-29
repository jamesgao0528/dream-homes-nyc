# Dream Homes NYC — Relational Database Design and Analytics System
Columbia APAN 5310 | Group 3  
Nam Ha · Weijia Gao · Yuboyi Dong · Jicheng Ge · Haozhe Zhang

## Project Overview
A 22-table PostgreSQL relational database for a fictional real estate agency operating across NY, NJ, and CT. Includes synthetic data generation, a dependency-ordered ETL pipeline, 12 analytical SQL queries, and Metabase dashboards.

## Setup
**Install dependencies:**
```bash
pip install sqlalchemy psycopg2-binary pandas
```

**Connection string** (adjust to your local Docker setup):
postgresql://postgres:postgres@localhost:5432/dreamhomes

## Notebook Run Order

1. `02_Dream Homes Data Generation.ipynb` — Generate synthetic CSVs into `dreamhomes_export/`
2. `03_etl.ipynb` — Execute schema (`dream_homes_schema_Final.sql`) and load all 22 tables
3. `04_queries.ipynb` — Run 12 analytical SQL queries against the loaded database

## Repository Contents
- `dream_homes_schema_Final.sql` - PostgreSQL DDL: 22 tables in 3NF with 4 trigger functions
- `02_Dream Homes Data Generation.ipynb` - Synthetic data generation using Python Faker
- `03_etl.ipynb` - ETL pipeline: schema execution, dependency-ordered loading, post-load validation
- `04_queries.ipynb` - 12 analytical SQL queries covering agent performance, pricing, client engagement, and lease operations
- `dreamhomes_export/` - Generated CSV files for all 22 tables
- `fix_csvs.py` - One-time script to correct data quality issues in generated CSVs
- `regenerate_client.py` - One-time script to regenerate the client table with a corrected pool size

## Notes
- All notebooks use `postgresql://postgres:postgres@localhost:5432/dreamhomes` by default
- Each team member may need to adjust the connection string to match their local Docker port
- `03_etl.ipynb` includes a TRUNCATE cell that resets all tables, run it before re-loading data
