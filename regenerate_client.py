"""
Dream Homes NYC — Client CSV Regeneration Script
=================================================
Run this BEFORE fix_csvs.py.

The problem:
    Only 15 buyers exist for 50 sale transactions.
    Only 10 renters exist for 30 lease transactions.
    fix_csvs.py Fix 5 reassigns client_ids to valid types,
    but with too few buyers/renters, each client appears in
    3-4 transactions — unrealistic.

The approach (SAFE — no child tables broken):
    All 50 existing client rows are KEPT INTACT because
    client_listing_interaction, appointment, property_transaction,
    and client_preference all reference client_ids 1–50.
    Replacing them would break every FK in those tables.

    Instead we ADD 35 new buyers (IDs 51–85) and
    20 new renters (IDs 86–105), giving fix_csvs.py Fix 5
    enough unique clients to assign one per transaction.

Run order:
    1. python regenerate_client.py   ← run this first
    2. python fix_csvs.py            ← then run this

Input:  reads dreamhomes_export/client.csv
Output: overwrites dreamhomes_export/client.csv with appended rows
        backs up original to dreamhomes_export/backup/client.csv
"""

import os
import shutil
import random
import pandas as pd
from faker import Faker
from datetime import datetime, timedelta

fake = Faker()
Faker.seed(99)
random.seed(99)

#  CONFIG
CSV_DIR    = 'dreamhomes_export'
BACKUP_DIR = os.path.join(CSV_DIR, 'backup')

#  BACKUP
os.makedirs(BACKUP_DIR, exist_ok=True)
src = os.path.join(CSV_DIR, 'client.csv')
dst = os.path.join(BACKUP_DIR, 'client.csv')
if os.path.exists(src):
    shutil.copy2(src, dst)
    print(f"Original backed up to {dst}\n")

#  LOAD EXISTING
existing = pd.read_csv(src)
print(f"Existing client rows: {len(existing)}")
print(f"Existing type breakdown:\n{existing['client_type'].value_counts().to_string()}\n")

# DETERMINE HOW MANY TO ADD
# Load transaction counts to set exact targets
sale  = pd.read_csv(os.path.join(CSV_DIR, 'sale_transaction.csv'))
lease = pd.read_csv(os.path.join(CSV_DIR, 'lease_transaction.csv'))

n_sale_trans  = len(sale)
n_lease_trans = len(lease)

current_buyers  = len(existing[existing['client_type'] == 'buyer'])
current_renters = len(existing[existing['client_type'] == 'renter'])

# Target: at least 1 unique buyer per sale transaction
#         at least 1 unique renter per lease transaction
# Add a small buffer (+5) so fix_csvs.py has variety to pick from
TARGET_BUYERS  = n_sale_trans  + 5
TARGET_RENTERS = n_lease_trans + 5

new_buyers  = max(0, TARGET_BUYERS  - current_buyers)
new_renters = max(0, TARGET_RENTERS - current_renters)

print(f"Sale transactions:  {n_sale_trans}  → target {TARGET_BUYERS} buyers  → adding {new_buyers}")
print(f"Lease transactions: {n_lease_trans} → target {TARGET_RENTERS} renters → adding {new_renters}")

#  GENERATE NEW ROWS
def random_created_date():
    """created_date spread across same range as existing clients: 2023–2026"""
    start = datetime(2023, 1, 1)
    end   = datetime(2026, 4, 14)
    return (start + timedelta(days=random.randint(0, (end - start).days))).strftime('%Y-%m-%d')

def make_client(client_id, client_type):
    first = fake.first_name()
    last  = fake.last_name()
    # Use client_id in email to guarantee uniqueness
    email = f"{first.lower()}.{last.lower()}.{client_id}@{fake.free_email_domain()}"
    phone = fake.numerify('###-###-####')
    return {
        'client_id':    client_id,
        'first_name':   first,
        'last_name':    last,
        'email':        email,
        'phone':        phone,
        'client_type':  client_type,
        'created_date': random_created_date(),
    }

new_rows = []
next_id  = existing['client_id'].max() + 1

for _ in range(new_buyers):
    new_rows.append(make_client(next_id, 'buyer'))
    next_id += 1

for _ in range(new_renters):
    new_rows.append(make_client(next_id, 'renter'))
    next_id += 1

new_df = pd.DataFrame(new_rows)

# COMBINE AND SAVE
combined = pd.concat([existing, new_df], ignore_index=True)

# Verify no duplicate emails or client_ids
assert combined['client_id'].duplicated().sum() == 0, "Duplicate client_ids found!"
assert combined['email'].duplicated().sum() == 0,     "Duplicate emails found!"

combined.to_csv(src, index=False)

#REPORT
print(f"\n DONE")
print(f"Total client rows:  {len(existing)} → {len(combined)}")
print(f"New type breakdown:\n{combined['client_type'].value_counts().to_string()}")
print(f"\nNew client_id range added: {existing['client_id'].max()+1} – {combined['client_id'].max()}")
print(f"\n No existing client_ids changed — all child table FKs remain valid.")
print(f"   client_listing_interaction, appointment, property_transaction,")
print(f"   and client_preference still reference valid client_ids.")
print(f"\n    python fix_csvs.py")
