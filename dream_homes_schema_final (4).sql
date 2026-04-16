-- Dream Homes NYC Relational Schema DDL
-- 21 Tables in 3NF, PostgreSQL compatible, and FK-safe load order
-- All data populated via Python Faker (synthetic)


-- GROUP 1: CORPORATE / HR

-- One record per Dream Homes NYC office location across NY, NJ, and CT
-- state_code is enforced as a CHECK constraint 

CREATE TABLE office (
    office_id SERIAL,
    office_name VARCHAR(100) NOT NULL,
    address VARCHAR(200) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state_code CHAR(2) NOT NULL,
    zip CHAR(5) NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(150),
    PRIMARY KEY (office_id),
    CHECK (state_code IN ('NY', 'NJ', 'CT'))
);


-- One record per Dream Homes NYC employee (agents and non-agent staff alike)
-- Agent-specific details are in the separate agent table below, 
-- so this table stays clean for all employees regardless of role
-- base_salary is optional since agents earn primarily via commission
-- office_id reflects current assignment only
CREATE TABLE employee (
    employee_id SERIAL,
    office_id INT NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    hire_date DATE NOT NULL,
    employment_type VARCHAR(20) NOT NULL,
    base_salary DECIMAL(10,2),
    PRIMARY KEY (employee_id),
    UNIQUE (email),
    FOREIGN KEY (office_id) REFERENCES office(office_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (employment_type IN ('full-time', 'part-time')),
    CHECK (base_salary IS NULL OR base_salary >= 0)
);


-- Agent is a 1:1 subtype of employee
-- agent_id is both PK and FK to employee, so no separate serial needed
-- commission_rate stored as decimal: e.g. 0.0300 = 3%
CREATE TABLE agent (
    agent_id INT NOT NULL,
    license_number VARCHAR(50) NOT NULL,
    commission_rate DECIMAL(5,4) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (agent_id),
    UNIQUE (license_number),
    FOREIGN KEY (agent_id) REFERENCES employee(employee_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (commission_rate BETWEEN 0.0000 AND 0.1000)
);


-- One row per revenue or expense entry per office, tracked over time
-- Kept separate from the office table because offices accumulate many financial records 
-- storing them all in one row would require repeating
-- columns and make historical tracking impossible

CREATE TABLE office_financials (
    record_id SERIAL,
    office_id INT NOT NULL,
    record_type VARCHAR(10) NOT NULL,
    category VARCHAR(100) NOT NULL,
    amount DECIMAL(12,2) NOT NULL,
    record_date DATE NOT NULL,
    notes VARCHAR(300),
    PRIMARY KEY (record_id),
    FOREIGN KEY (office_id) REFERENCES office(office_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (record_type IN ('revenue', 'expense')),
    CHECK (amount > 0)
);



-- GROUP 2: GEOGRAPHIC / REFERENCE


-- School district reference data linked to properties by zip code at ETL time
-- district_name, city, state_code, and zip describe the district's administrative location
-- A district can span multiple zip codes in practice, so district_id does not
-- functionally determine a single zip or city (no transitive dependency)
-- enrollment and student_teacher_ratio are nullable since not all districts
-- will have complete data

CREATE TABLE school_district (
    district_id SERIAL,
    district_name VARCHAR(200) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state_code CHAR(2) NOT NULL,
    zip CHAR(5) NOT NULL,
    enrollment INT,
    student_teacher_ratio DECIMAL(5,2),
    PRIMARY KEY (district_id),
    CHECK (state_code IN ('NY', 'NJ', 'CT')),
    CHECK (enrollment IS NULL OR enrollment >= 0),
    CHECK (student_teacher_ratio IS NULL OR student_teacher_ratio > 0)
);


-- Neighborhood reference data used for geographic grouping and filtering
-- Storing neighborhoods as a proper table ensure consistent grouping 
-- without spelling variations

CREATE TABLE neighborhood (
    neighborhood_id SERIAL,
    neighborhood_name VARCHAR(100) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state_code CHAR(2) NOT NULL,
    zip CHAR(5) NOT NULL,
    PRIMARY KEY (neighborhood_id),
    CHECK (state_code IN ('NY', 'NJ', 'CT'))
);



-- GROUP 3: PROPERTY & LISTINGS


-- Amenity types are stored as a separate reference table rather than a CHECK constraint
-- as amenity types can grow over time as new property features are added
-- A CHECK constraint would require a schema change every time a new amenity is added
-- New amenities can be added by inserting a row here without modifying the schema

CREATE TABLE amenity (
    amenity_id SERIAL,
    amenity_name VARCHAR(100) NOT NULL,
    PRIMARY KEY (amenity_id),
    UNIQUE (amenity_name)
);


-- One record per physical property in the Dream Homes NYC portfolio
-- city, state_code, and zip reflect the property's actual mailing address
-- neighborhood_id is a separate logical grouping used for market search and filtering
-- These are intentionally independent: a neighborhood can span multiple zip codes,
-- and a zip code can contain parts of multiple neighborhoods
-- Storing both does not create a transitive dependency because neighborhood_id does not 
-- determine city, state, or zip in the real world
-- district_id and neighborhood_id are both nullable,
-- not every property will match a district or neighborhood in the synthetic dataset
-- year_built uses SMALLINT as PostgreSQL has no dedicated YEAR type

CREATE TABLE property (
    property_id SERIAL,
    district_id INT,
    neighborhood_id INT,
    address VARCHAR(200) NOT NULL,
    city VARCHAR(100) NOT NULL,
    state_code CHAR(2) NOT NULL,
    zip CHAR(5) NOT NULL,
    property_type VARCHAR(20) NOT NULL,
    bedrooms INT,
    bathrooms DECIMAL(3,1),
    sqft INT,
    lot_size_acres DECIMAL(8,2),
    year_built SMALLINT,
    PRIMARY KEY (property_id),
    FOREIGN KEY (district_id) REFERENCES school_district(district_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    FOREIGN KEY (neighborhood_id) REFERENCES neighborhood(neighborhood_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CHECK (state_code IN ('NY', 'NJ', 'CT')),
    CHECK (property_type IN ('house', 'townhouse', 'apartment', 'condo', 'co-op')),
    CHECK (year_built BETWEEN 1800 AND 2030),
    CHECK (bedrooms >= 0),
    CHECK (bathrooms >= 0),
    CHECK (sqft > 0),
    CHECK (lot_size_acres IS NULL OR lot_size_acres > 0)
);


-- Many-to-many between property and amenity
-- A property has many amenities and an amenity applies to many properties
-- Bridge table resolves many-to-many and keeps both sides in 3NF

CREATE TABLE property_amenity (
    property_id INT NOT NULL,
    amenity_id INT NOT NULL,
    PRIMARY KEY (property_id, amenity_id),
    FOREIGN KEY (property_id) REFERENCES property(property_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (amenity_id) REFERENCES amenity(amenity_id)
        ON UPDATE CASCADE ON DELETE CASCADE
);


-- One record per listing when a property is put on the market for sale or rent
-- status tracks whether the listing is currently active, sold, rented, or withdrawn
-- status is updated automatically by a trigger when a transaction is inserted
-- To find the office associated with a listing, join:
-- listing.agent_id -> agent -> employee.office_id -> office

CREATE TABLE listing (
    listing_id SERIAL,
    property_id INT NOT NULL,
    agent_id INT NOT NULL,
    list_price DECIMAL(12,2) NOT NULL,
    list_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    listing_type VARCHAR(10) NOT NULL,
    PRIMARY KEY (listing_id),
    FOREIGN KEY (property_id) REFERENCES property(property_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (agent_id) REFERENCES agent(agent_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (status IN ('active', 'sold', 'rented', 'withdrawn')),
    CHECK (listing_type IN ('sale', 'lease')),
    CHECK (list_price > 0)
);


-- Tracks every price change for a listing over time
-- Kept separate from listing because a price can change multiple times
-- before a listing closes, and storing each change here preserves the
-- full history without overwriting previous values

CREATE TABLE listing_price_history (
    history_id SERIAL,
    listing_id INT NOT NULL,
    old_price DECIMAL(12,2) NOT NULL,
    new_price DECIMAL(12,2) NOT NULL,
    change_date DATE NOT NULL,
    change_reason VARCHAR(200),
    PRIMARY KEY (history_id),
    FOREIGN KEY (listing_id) REFERENCES listing(listing_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CHECK (old_price > 0),
    CHECK (new_price > 0),
    CHECK (old_price <> new_price)
);



-- GROUP 4: MARKET DATA

-- Monthly market statistics by zip code, sourced from external data
-- No FK on zip intentionally as external zip codes may not match internal ones exactly
-- Joined to internal data analytically by zip value when needed
-- period_month is stored as the first day of each month (e.g. 2024-01-01 = January 2024)
-- UNIQUE on (zip, period_month) prevents duplicate records per zip per month

CREATE TABLE zip_market_trend (
    trend_id SERIAL,
    zip CHAR(5) NOT NULL,
    period_month DATE NOT NULL,
    median_sale_price DECIMAL(12,2),
    median_list_price DECIMAL(12,2),
    homes_sold INT,
    avg_days_on_market DECIMAL(6,2),
    price_drop_count INT,
    PRIMARY KEY (trend_id),
    UNIQUE (zip, period_month),
    CHECK (homes_sold >= 0),
    CHECK (avg_days_on_market >= 0),
    CHECK (price_drop_count >= 0),
    CHECK (median_sale_price IS NULL OR median_sale_price > 0),
    CHECK (median_list_price IS NULL OR median_list_price > 0)
);



-- GROUP 5: CLIENTS & INTERACTIONS


-- client_type distinguishes buyers, sellers, renters, and landlords
CREATE TABLE client (
    client_id SERIAL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    client_type VARCHAR(20) NOT NULL,
    created_date DATE NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (client_id),
    UNIQUE (email),
    CHECK (client_type IN ('buyer', 'seller', 'renter', 'landlord'))
);


-- Stores each client's property search preferences
-- Kept separate from client to avoid empty columns for clients with no preferences
-- UNIQUE on client_id enforces a one-to-one relationship with client
-- Geographic preference fields are intentionally independent:
-- preferred_neighborhood_id is used for specific neighborhood targeting
-- preferred_city, preferred_state, and preferred_zip are used for broad
-- geographic preferences when no specific neighborhood is selected
-- ETL enforces that when preferred_neighborhood_id is set, preferred_city,
-- preferred_state, and preferred_zip are left NULL to avoid contradictions

CREATE TABLE client_preference (
    preference_id SERIAL,
    client_id INT NOT NULL,
    preferred_property_type VARCHAR(20),
    preferred_state CHAR(2),
    preferred_city VARCHAR(100),
    preferred_neighborhood_id INT,
    preferred_zip CHAR(5),
    min_bedrooms INT,
    min_bathrooms DECIMAL(3,1),
    budget_min DECIMAL(12,2),
    budget_max DECIMAL(12,2),
    PRIMARY KEY (preference_id),
    UNIQUE (client_id),
    FOREIGN KEY (client_id) REFERENCES client(client_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (preferred_neighborhood_id) REFERENCES neighborhood(neighborhood_id)
        ON UPDATE CASCADE ON DELETE SET NULL,
    CHECK (preferred_state IS NULL OR preferred_state IN ('NY', 'NJ', 'CT')),
    CHECK (preferred_property_type IS NULL OR preferred_property_type IN ('house', 'townhouse', 'apartment', 'condo', 'co-op')),
    CHECK (budget_max IS NULL OR budget_max >= budget_min),
    CHECK (min_bedrooms IS NULL OR min_bedrooms >= 0),
    CHECK (min_bathrooms IS NULL OR min_bathrooms >= 0),
    CHECK (budget_min IS NULL OR budget_min >= 0),
    CHECK (
        preferred_neighborhood_id IS NULL OR
        (preferred_city IS NULL AND preferred_state IS NULL AND preferred_zip IS NULL)
    )
);


-- Tracks client engagement with listings before an appointment is booked
-- Interaction types: saved, viewed, or inquired
-- Supports conversion funnel analysis: viewed -> appointment -> closed
-- Many-to-many between client and listing handled via this bridge table
-- UNIQUE on client_id, listing_id, interaction_type, prevents duplicates

CREATE TABLE client_listing_interaction (
    interaction_id SERIAL,
    client_id INT NOT NULL,
    listing_id INT NOT NULL,
    interaction_type VARCHAR(20) NOT NULL,
    interaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
    PRIMARY KEY (interaction_id),
    UNIQUE (client_id, listing_id, interaction_type),
    FOREIGN KEY (client_id) REFERENCES client(client_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (listing_id) REFERENCES listing(listing_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CHECK (interaction_type IN ('saved', 'viewed', 'inquired'))
);


-- Scheduled meetings between a client and agent for a specific listing
-- outcome defaults to 'pending' when first created and is updated after the appointment takes place
-- agent_id is reachable via listing_id -> listing.agent_id
-- To get the agent, join through listing

CREATE TABLE appointment (
    appointment_id SERIAL,
    listing_id INT NOT NULL,
    client_id INT NOT NULL,
    scheduled_datetime TIMESTAMP NOT NULL,
    appointment_type VARCHAR(20) NOT NULL,
    outcome VARCHAR(20) NOT NULL DEFAULT 'pending',
    PRIMARY KEY (appointment_id),
    FOREIGN KEY (listing_id) REFERENCES listing(listing_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (client_id) REFERENCES client(client_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (appointment_type IN ('viewing', 'consultation', 'offer_review')),
    CHECK (outcome IN ('pending', 'completed', 'cancelled', 'no_show', 'offer_made'))
);


-- Open house events for a listed property
-- start_datetime and end_datetime use TIMESTAMP for consistency with appointment
-- agent_id is reachable via listing_id -> listing.agent_id
-- To get the agent, join through listing

CREATE TABLE open_house (
    open_house_id SERIAL,
    listing_id INT NOT NULL,
    start_datetime TIMESTAMP NOT NULL,
    end_datetime TIMESTAMP NOT NULL,
    attendee_count INT NOT NULL DEFAULT 0,
    PRIMARY KEY (open_house_id),
    FOREIGN KEY (listing_id) REFERENCES listing(listing_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (end_datetime > start_datetime),
    CHECK (attendee_count >= 0)
);



-- GROUP 6: TRANSACTIONS

-- Parent table for all completed transactions.
-- Stores fields common to both sales and leases: listing, client, and date
-- agent_id is not stored here since it is already reachable via:
-- listing_id -> listing.agent_id. To get the agent, join through listing
-- To determine whether a transaction is a sale or lease, join to sale_transaction,
-- or lease_transaction, whichever has a matching transaction_id

CREATE TABLE property_transaction (
    transaction_id SERIAL,
    listing_id INT NOT NULL,
    client_id INT NOT NULL,
    transaction_date DATE NOT NULL,
    PRIMARY KEY (transaction_id),
    FOREIGN KEY (listing_id) REFERENCES listing(listing_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    FOREIGN KEY (client_id) REFERENCES client(client_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
);


-- Sale-specific details: final price, closing date, and mortgage type
-- Child of property_transaction (one-to-one)
-- Sale fields are kept here to avoid empty columns for lease records

CREATE TABLE sale_transaction (
    transaction_id INT NOT NULL,
    sale_price DECIMAL(12,2) NOT NULL,
    closing_date DATE NOT NULL,
    mortgage_type VARCHAR(20),
    PRIMARY KEY (transaction_id),
    FOREIGN KEY (transaction_id) REFERENCES property_transaction(transaction_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CHECK (mortgage_type IN ('conventional', 'FHA', 'VA', 'cash', 'other')),
    CHECK (sale_price > 0)
);


-- Lease-specific details: monthly rent, lease dates, and security deposit
-- Child of property_transaction (one-to-one)

CREATE TABLE lease_transaction (
    transaction_id INT NOT NULL,
    monthly_rent DECIMAL(10,2) NOT NULL,
    lease_start DATE NOT NULL,
    lease_end DATE NOT NULL,
    security_deposit DECIMAL(10,2),
    PRIMARY KEY (transaction_id),
    FOREIGN KEY (transaction_id) REFERENCES property_transaction(transaction_id)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CHECK (lease_end > lease_start),
    CHECK (monthly_rent > 0),
    CHECK (security_deposit >= 0)
);


-- One commission record per completed transaction
-- commission_amount is calculated at transaction time:
-- sale: ROUND(sale_price * agent.commission_rate, 2)
-- lease: ROUND(monthly_rent * 12 * agent.commission_rate, 2)
-- paid_date records when payment was made, NULL means unpaid
-- Use paid_date IS NOT NULL to check payment status

CREATE TABLE commission (
    commission_id SERIAL,
    transaction_id INT NOT NULL,
    commission_amount DECIMAL(12,2) NOT NULL,
    paid_date DATE,
    PRIMARY KEY (commission_id),
    UNIQUE (transaction_id),
    FOREIGN KEY (transaction_id) REFERENCES property_transaction(transaction_id)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    CHECK (commission_amount >= 0)
);




-- TRIGGER 1: Update listing status on transaction insert
-- Fires after sale_transaction or lease_transaction is inserted
-- Looks up listing_id from property_transaction and sets status

CREATE OR REPLACE FUNCTION update_listing_status()
RETURNS TRIGGER AS $$
DECLARE
    v_listing_id INT;
    v_status VARCHAR(20);
BEGIN
    SELECT listing_id INTO v_listing_id
    FROM property_transaction
    WHERE transaction_id = NEW.transaction_id;

    IF TG_TABLE_NAME = 'sale_transaction' THEN
        v_status := 'sold';
    ELSE
        v_status := 'rented';
    END IF;

    UPDATE listing
    SET status = v_status
    WHERE listing_id = v_listing_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_listing_status_sale
AFTER INSERT ON sale_transaction
FOR EACH ROW
EXECUTE FUNCTION update_listing_status();

CREATE TRIGGER trg_update_listing_status_lease
AFTER INSERT ON lease_transaction
FOR EACH ROW
EXECUTE FUNCTION update_listing_status();



-- TRIGGER 2: Enforce subtype existence 
-- every property_transaction must have exactly one subtype row before the transaction commits
-- Uses DEFERRABLE INITIALLY DEFERRED so the check runs at commit time, 
-- after the subtype row has been inserted.

CREATE OR REPLACE FUNCTION enforce_subtype_exists()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM sale_transaction  WHERE transaction_id = NEW.transaction_id
    ) AND NOT EXISTS (
        SELECT 1 FROM lease_transaction WHERE transaction_id = NEW.transaction_id
    ) THEN
        RAISE EXCEPTION
            'property_transaction % has no subtype row in sale_transaction or lease_transaction.',
            NEW.transaction_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_enforce_subtype_exists
AFTER INSERT ON property_transaction
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION enforce_subtype_exists();



-- TRIGGER 3: Enforce mutually exclusive subtypes 
-- a property_transaction cannot have both a sale_transaction and a lease_transaction row

CREATE OR REPLACE FUNCTION enforce_subtype_disjoint()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'sale_transaction' THEN
        IF EXISTS (
            SELECT 1 FROM lease_transaction WHERE transaction_id = NEW.transaction_id
        ) THEN
            RAISE EXCEPTION
                'transaction_id % already has a lease_transaction row.',
                NEW.transaction_id;
        END IF;
    ELSIF TG_TABLE_NAME = 'lease_transaction' THEN
        IF EXISTS (
            SELECT 1 FROM sale_transaction WHERE transaction_id = NEW.transaction_id
        ) THEN
            RAISE EXCEPTION
                'transaction_id % already has a sale_transaction row.',
                NEW.transaction_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_disjoint_sale
BEFORE INSERT ON sale_transaction
FOR EACH ROW
EXECUTE FUNCTION enforce_subtype_disjoint();

CREATE TRIGGER trg_disjoint_lease
BEFORE INSERT ON lease_transaction
FOR EACH ROW
EXECUTE FUNCTION enforce_subtype_disjoint();



-- TRIGGER 4: Enforce listing type matches transaction subtype
-- Prevents a lease_transaction on a 'sale' listing and vice versa

CREATE OR REPLACE FUNCTION enforce_listing_type_match()
RETURNS TRIGGER AS $$
DECLARE
    v_listing_type VARCHAR(10);
BEGIN
    SELECT l.listing_type INTO v_listing_type
    FROM listing l
    JOIN property_transaction pt ON l.listing_id = pt.listing_id
    WHERE pt.transaction_id = NEW.transaction_id;

    IF TG_TABLE_NAME = 'sale_transaction' AND v_listing_type != 'sale' THEN
        RAISE EXCEPTION
            'transaction_id % links to a listing of type %, cannot insert sale_transaction.',
            NEW.transaction_id, v_listing_type;
    ELSIF TG_TABLE_NAME = 'lease_transaction' AND v_listing_type != 'lease' THEN
        RAISE EXCEPTION
            'transaction_id % links to a listing of type %, cannot insert lease_transaction.',
            NEW.transaction_id, v_listing_type;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_listing_type_match_sale
BEFORE INSERT ON sale_transaction
FOR EACH ROW
EXECUTE FUNCTION enforce_listing_type_match();

CREATE TRIGGER trg_listing_type_match_lease
BEFORE INSERT ON lease_transaction
FOR EACH ROW
EXECUTE FUNCTION enforce_listing_type_match();