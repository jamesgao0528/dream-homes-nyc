"""
Dream Homes NYC — CSV Data Fix Script
======================================
Run this script from the folder containing your dreamhomes_export CSVs.

Usage:
    python fix_csvs.py

Input:  reads CSVs from ./dreamhomes_export/
Output: overwrites the same files with fixes applied
        (originals are backed up to ./dreamhomes_export/backup/)

Fixes applied:
    Fix 1  — appointment.scheduled_datetime: spread across Jan 2024–Apr 2026, business hours
    Fix 2  — property_transaction.transaction_date: must be >= listing list_date
    Fix 3  — listing_price_history.change_date: must be >= listing list_date
    Fix 4  — sale_transaction.sale_price: constrained to 80–120% of list_price
    Fix 5  — property_transaction.client_id: buyers only for sales, renters only for leases
    Fix 6  — appointment.client_id: buyers and renters only (no sellers/landlords)
    Fix 7  — sale_transaction.closing_date: exactly 7 days after transaction_date
    Fix 8  — property_amenity: remove Doorman/Concierge/Bike Room/Rooftop Deck from houses/townhouses
"""

import os
import shutil
import random
import pandas as pd
from datetime import datetime, timedelta

random.seed(42)

# ── CONFIG ────────────────────────────────────────────────────────────────────
CSV_DIR = 'dreamhomes_export'   # folder containing your CSVs
BACKUP_DIR = os.path.join(CSV_DIR, 'backup')

# ── HELPERS ───────────────────────────────────────────────────────────────────
def load(filename):
    return pd.read_csv(os.path.join(CSV_DIR, filename))

def save(df, filename):
    df.to_csv(os.path.join(CSV_DIR, filename), index=False)
    print(f"  saved {filename} ({len(df)} rows)")

def backup(filename):
    src = os.path.join(CSV_DIR, filename)
    dst = os.path.join(BACKUP_DIR, filename)
    if os.path.exists(src):
        shutil.copy2(src, dst)

# ── BACKUP ────────────────────────────────────────────────────────────────────
os.makedirs(BACKUP_DIR, exist_ok=True)
for f in ['appointment.csv', 'property_transaction.csv', 'listing_price_history.csv',
          'sale_transaction.csv', 'property_amenity.csv']:
    backup(f)
print(f"Originals backed up to {BACKUP_DIR}/\n")

# ── LOAD ALL NEEDED FILES ─────────────────────────────────────────────────────
listing      = load('listing.csv')
appointment  = load('appointment.csv')
prop_trans   = load('property_transaction.csv')
sale         = load('sale_transaction.csv')
lease        = load('lease_transaction.csv')
lph          = load('listing_price_history.csv')
client       = load('client.csv')
prop         = load('property.csv')
prop_amenity = load('property_amenity.csv')
amenity      = load('amenity.csv')

# Parse dates
listing['list_date']             = pd.to_datetime(listing['list_date'])
prop_trans['transaction_date']   = pd.to_datetime(prop_trans['transaction_date'])
lph['change_date']               = pd.to_datetime(lph['change_date'])
sale['closing_date']             = pd.to_datetime(sale['closing_date'])

# Lookup maps
listing_date_map    = listing.set_index('listing_id')['list_date'].to_dict()
listing_price_map   = listing.set_index('listing_id')['list_price'].to_dict()
trans_listing_map   = prop_trans.set_index('transaction_id')['listing_id'].to_dict()

sale_trans_ids  = set(sale['transaction_id'])
lease_trans_ids = set(lease['transaction_id'])

buyer_ids   = client[client['client_type'] == 'buyer']['client_id'].tolist()
renter_ids  = client[client['client_type'] == 'renter']['client_id'].tolist()
eligible_appt_client_ids = client[client['client_type'].isin(['buyer', 'renter'])]['client_id'].tolist()

# ── FIX 1: appointment.scheduled_datetime ────────────────────────────────────
print("Fix 1 — appointment.scheduled_datetime")
def random_appointment_datetime():
    start = datetime(2024, 1, 1)
    end   = datetime(2026, 4, 16)
    base  = start + timedelta(days=random.randint(0, (end - start).days))
    return base.replace(
        hour=random.randint(9, 17),
        minute=random.choice([0, 15, 30, 45]),
        second=0
    )

appointment['scheduled_datetime'] = [
    random_appointment_datetime() for _ in range(len(appointment))
]
print(f"  date range: {appointment['scheduled_datetime'].min()} → {appointment['scheduled_datetime'].max()}")
print(f"  unique dates: {appointment['scheduled_datetime'].dt.date.nunique()}")

# ── FIX 2: property_transaction.transaction_date >= list_date ─────────────────
print("\nFix 2 — property_transaction.transaction_date")
def fix_transaction_date(row):
    list_dt = listing_date_map.get(row['listing_id'])
    if list_dt is not None and row['transaction_date'] < list_dt:
        return list_dt + timedelta(days=random.randint(1, 180))
    return row['transaction_date']

prop_trans['transaction_date'] = prop_trans.apply(fix_transaction_date, axis=1)

still_bad = prop_trans.apply(
    lambda r: r['transaction_date'] < listing_date_map.get(r['listing_id'], pd.Timestamp.min), axis=1
).sum()
print(f"  transactions still before list_date: {still_bad} (should be 0)")

# ── FIX 3: listing_price_history.change_date >= list_date ────────────────────
print("\nFix 3 — listing_price_history.change_date")
def fix_change_date(row):
    list_dt = listing_date_map.get(row['listing_id'])
    if list_dt is not None and row['change_date'] < list_dt:
        return list_dt + timedelta(days=random.randint(1, 90))
    return row['change_date']

lph['change_date'] = lph.apply(fix_change_date, axis=1)

still_bad = lph.apply(
    lambda r: r['change_date'] < listing_date_map.get(r['listing_id'], pd.Timestamp.min), axis=1
).sum()
print(f"  price changes still before list_date: {still_bad} (should be 0)")

# ── FIX 4: sale_transaction.sale_price within 80–120% of list_price ──────────
print("\nFix 4 — sale_transaction.sale_price")
def fix_sale_price(row):
    listing_id = trans_listing_map.get(row['transaction_id'])
    list_price = listing_price_map.get(listing_id)
    if list_price:
        ratio = row['sale_price'] / list_price
        if ratio > 1.20 or ratio < 0.80:
            return round(list_price * random.uniform(0.80, 1.20), 2)
    return row['sale_price']

sale['sale_price'] = sale.apply(fix_sale_price, axis=1)

# Verify
sale['_listing_id'] = sale['transaction_id'].map(trans_listing_map)
sale['_list_price'] = sale['_listing_id'].map(listing_price_map)
sale['_ratio'] = sale['sale_price'] / sale['_list_price']
outside = ((sale['_ratio'] > 1.20) | (sale['_ratio'] < 0.80)).sum()
print(f"  prices outside 80–120% range: {outside} (should be 0)")
print(f"  ratio range: {sale['_ratio'].min():.2f} – {sale['_ratio'].max():.2f}")
sale.drop(columns=['_listing_id', '_list_price', '_ratio'], inplace=True)

# ── FIX 5: property_transaction.client_id must match transaction type ─────────
print("\nFix 5 — property_transaction.client_id")

# Re-build trans_listing_map after Fix 2 updated transaction_date
trans_listing_map = prop_trans.set_index('transaction_id')['listing_id'].to_dict()

def fix_client_id(row):
    if row['transaction_id'] in sale_trans_ids and row['client_id'] not in buyer_ids:
        return random.choice(buyer_ids)
    if row['transaction_id'] in lease_trans_ids and row['client_id'] not in renter_ids:
        return random.choice(renter_ids)
    return row['client_id']

prop_trans['client_id'] = prop_trans.apply(fix_client_id, axis=1)

check = prop_trans.merge(client[['client_id', 'client_type']], on='client_id')
sale_bad  = ((check['transaction_id'].isin(sale_trans_ids))  & (check['client_type'] != 'buyer')).sum()
lease_bad = ((check['transaction_id'].isin(lease_trans_ids)) & (check['client_type'] != 'renter')).sum()
print(f"  sale transactions with non-buyer client: {sale_bad} (should be 0)")
print(f"  lease transactions with non-renter client: {lease_bad} (should be 0)")

# ── FIX 6: appointment.client_id must be buyer or renter ─────────────────────
print("\nFix 6 — appointment.client_id")
appointment['client_id'] = appointment['client_id'].apply(
    lambda cid: random.choice(eligible_appt_client_ids)
    if cid not in eligible_appt_client_ids else cid
)

appt_check = appointment.merge(client[['client_id', 'client_type']], on='client_id')
bad_appt = (~appt_check['client_type'].isin(['buyer', 'renter'])).sum()
print(f"  appointments with seller/landlord client: {bad_appt} (should be 0)")

# ── FIX 7: sale_transaction.closing_date = transaction_date + 7 days ─────────
print("\nFix 7 — sale_transaction.closing_date")
trans_date_map = prop_trans.set_index('transaction_id')['transaction_date'].to_dict()

sale['closing_date'] = sale['transaction_id'].apply(
    lambda tid: (pd.to_datetime(trans_date_map[tid]) + timedelta(days=7)).date()
)

diffs = sale['transaction_id'].apply(
    lambda tid: (pd.to_datetime(sale.loc[sale['transaction_id']==tid, 'closing_date'].values[0])
                 - pd.to_datetime(trans_date_map[tid])).days
)
print(f"  closing date offset — min: {diffs.min()} days, max: {diffs.max()} days (all should be 7)")

# ── FIX 8: property_amenity — remove building amenities from houses/townhouses
print("\nFix 8 — property_amenity")
BUILDING_ONLY = {'Doorman', 'Concierge', 'Bike Room', 'Rooftop Deck'}
building_amenity_ids   = amenity[amenity['amenity_name'].isin(BUILDING_ONLY)]['amenity_id'].tolist()
house_townhouse_ids    = prop[prop['property_type'].isin(['house', 'townhouse'])]['property_id'].tolist()

before = len(prop_amenity)
prop_amenity = prop_amenity[~(
    prop_amenity['property_id'].isin(house_townhouse_ids) &
    prop_amenity['amenity_id'].isin(building_amenity_ids)
)]
after = len(prop_amenity)
print(f"  removed {before - after} rows ({before} → {after})")

# ── SAVE ALL FIXED FILES ──────────────────────────────────────────────────────
print("\n=== SAVING FIXED CSVs ===")
save(appointment,  'appointment.csv')
save(prop_trans,   'property_transaction.csv')
save(lph,          'listing_price_history.csv')
save(sale,         'sale_transaction.csv')
save(prop_amenity, 'property_amenity.csv')

print("\n✅ All fixes applied successfully.")
print(f"   Originals preserved in {BACKUP_DIR}/")
