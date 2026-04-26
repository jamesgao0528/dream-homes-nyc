# Dream Homes NYC

## Setup
Install dependencies:pip install -r requirements.txt
## Connection String
postgresql://postgres:123@localhost:5432/dreamhomes
## Notebook Run Order
1. `01_schema.ipynb`         Create schema
2. `02_Dream_Homes_Data_Generation.ipynb`   Generate synthetic data and insert into database
3. `03_etl.ipynb`            Load CSVs into database
4. `04_queries.ipynb`        Run analytical queries