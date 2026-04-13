# Dream Homes NYC

## Setup
Install dependencies:pip install -r requirements.txt
## Connection String
postgresql://postgres:123@localhost:5432/dreamhomes
## Notebook Run Order
1. `01_schema.ipynb` — Create schema
2. `02_etl.ipynb` — Load CSVs into database
3. `03_queries.ipynb` — Run analytical queries