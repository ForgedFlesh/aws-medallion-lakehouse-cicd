-- =========================================================
-- Classic Models source database bootstrap
-- =========================================================
-- Initial rows are deliberately timestamped for yesterday.
-- Our Airflow daily pipeline processes the previous business day.
-- =========================================================

SET @seed_ts = TIMESTAMP(
    DATE_SUB(CURDATE(), INTERVAL 1 DAY),
    '10:00:00'
);

-- =========================================================
-- 1. OFFICES
-- =========================================================

CREATE TABLE IF NOT EXISTS offices (
    officeCode   VARCHAR(10) PRIMARY KEY,
    city         VARCHAR(50) NOT NULL,
    phone        VARCHAR(50),
    addressLine1 VARCHAR(100),
    addressLine2 VARCHAR(100),
    state        VARCHAR(50),
    country      VARCHAR(50) NOT NULL,
    postalCode   VARCHAR(20),
    territory    VARCHAR(20),
    updated_at   TIMESTAMP NOT NULL
);

-- =========================================================
-- 2. EMPLOYEES
-- =========================================================

CREATE TABLE IF NOT EXISTS employees (
    employeeNumber INT PRIMARY KEY,
    lastName       VARCHAR(50) NOT NULL,
    firstName      VARCHAR(50) NOT NULL,
    extension      VARCHAR(20),
    email          VARCHAR(100),
    officeCode     VARCHAR(10),
    reportsTo      INT,
    jobTitle       VARCHAR(50),
    updated_at     TIMESTAMP NOT NULL
);

-- =========================================================
-- 3. CUSTOMERS
-- =========================================================

CREATE TABLE IF NOT EXISTS customers (
    customerNumber         INT PRIMARY KEY,
    customerName           VARCHAR(100) NOT NULL,
    contactLastName        VARCHAR(50),
    contactFirstName       VARCHAR(50),
    phone                  VARCHAR(50),
    addressLine1           VARCHAR(100),
    addressLine2           VARCHAR(100),
    city                   VARCHAR(50),
    state                  VARCHAR(50),
    postalCode             VARCHAR(20),
    country                VARCHAR(50),
    salesRepEmployeeNumber INT,
    creditLimit            DECIMAL(10,2),
    updated_at             TIMESTAMP NOT NULL
);

-- =========================================================
-- 4. PRODUCT LINES
-- =========================================================

CREATE TABLE IF NOT EXISTS productlines (
    productLine     VARCHAR(50) PRIMARY KEY,
    textDescription TEXT,
    htmlDescription TEXT,
    updated_at       TIMESTAMP NOT NULL
);

-- =========================================================
-- 5. PRODUCTS
-- =========================================================

CREATE TABLE IF NOT EXISTS products (
    productCode        VARCHAR(50) PRIMARY KEY,
    productName        VARCHAR(100) NOT NULL,
    productLine        VARCHAR(50),
    productScale       VARCHAR(20),
    productVendor      VARCHAR(100),
    productDescription TEXT,
    quantityInStock    INT,
    buyPrice           DECIMAL(10,2),
    MSRP               DECIMAL(10,2),
    updated_at         TIMESTAMP NOT NULL
);

-- =========================================================
-- 6. ORDERS
-- =========================================================

CREATE TABLE IF NOT EXISTS orders (
    orderNumber    INT PRIMARY KEY,
    orderDate      DATE NOT NULL,
    requiredDate   DATE,
    shippedDate    DATE,
    status         VARCHAR(30),
    comments       TEXT,
    customerNumber INT,
    updated_at     TIMESTAMP NOT NULL
);

-- =========================================================
-- 7. ORDER DETAILS
-- =========================================================

CREATE TABLE IF NOT EXISTS orderdetails (
    orderNumber     INT NOT NULL,
    productCode     VARCHAR(50) NOT NULL,
    quantityOrdered INT NOT NULL,
    priceEach       DECIMAL(10,2) NOT NULL,
    orderLineNumber INT NOT NULL,
    updated_at      TIMESTAMP NOT NULL,

    PRIMARY KEY (orderNumber, orderLineNumber)
);

-- =========================================================
-- 8. PAYMENTS
-- =========================================================

CREATE TABLE IF NOT EXISTS payments (
    customerNumber INT NOT NULL,
    checkNumber    VARCHAR(50) NOT NULL,
    paymentDate    DATE,
    amount         DECIMAL(10,2),
    updated_at     TIMESTAMP NOT NULL,

    PRIMARY KEY (customerNumber, checkNumber)
);

-- =========================================================
-- INITIAL SAMPLE DATA
-- =========================================================

INSERT IGNORE INTO offices (
    officeCode,
    city,
    phone,
    addressLine1,
    country,
    postalCode,
    territory,
    updated_at
)
VALUES
(
    '1',
    'San Francisco',
    '+1 650 219 4782',
    '100 Market Street',
    'USA',
    '94080',
    'NA',
    @seed_ts
),
(
    '2',
    'Boston',
    '+1 617 555 0100',
    '200 Atlantic Avenue',
    'USA',
    '02110',
    'NA',
    @seed_ts
);

-- ---------------------------------------------------------

INSERT IGNORE INTO employees (
    employeeNumber,
    lastName,
    firstName,
    extension,
    email,
    officeCode,
    reportsTo,
    jobTitle,
    updated_at
)
VALUES
(
    1001,
    'Murphy',
    'Diane',
    'x5800',
    'dmurphy@example.com',
    '1',
    NULL,
    'President',
    @seed_ts
),
(
    1002,
    'Patterson',
    'Mary',
    'x4611',
    'mpatterson@example.com',
    '2',
    1001,
    'Sales Rep',
    @seed_ts
);

-- ---------------------------------------------------------

INSERT IGNORE INTO customers (
    customerNumber,
    customerName,
    contactLastName,
    contactFirstName,
    phone,
    addressLine1,
    city,
    state,
    postalCode,
    country,
    salesRepEmployeeNumber,
    creditLimit,
    updated_at
)
VALUES
(
    101,
    'Alpha Retail',
    'Smith',
    'John',
    '555-0101',
    '10 First Street',
    'New York',
    'NY',
    '10001',
    'USA',
    1002,
    50000.00,
    @seed_ts
),
(
    102,
    'Beta Stores',
    'Brown',
    'Emma',
    '555-0102',
    '20 Second Street',
    'Boston',
    'MA',
    '02110',
    'USA',
    1002,
    75000.00,
    @seed_ts
),
(
    103,
    'Gamma Traders',
    'Wilson',
    'David',
    '555-0103',
    '30 Third Street',
    'Chicago',
    'IL',
    '60601',
    'USA',
    1002,
    40000.00,
    @seed_ts
);

-- ---------------------------------------------------------

INSERT IGNORE INTO productlines (
    productLine,
    textDescription,
    htmlDescription,
    updated_at
)
VALUES
(
    'Classic Cars',
    'Classic automobile models',
    NULL,
    @seed_ts
),
(
    'Motorcycles',
    'Motorcycle models',
    NULL,
    @seed_ts
);

-- ---------------------------------------------------------

INSERT IGNORE INTO products (
    productCode,
    productName,
    productLine,
    productScale,
    productVendor,
    productDescription,
    quantityInStock,
    buyPrice,
    MSRP,
    updated_at
)
VALUES
(
    'S10_001',
    '1969 Ford Mustang',
    'Classic Cars',
    '1:18',
    'AutoArt Studio',
    'Classic Ford Mustang model',
    100,
    45.00,
    95.00,
    @seed_ts
),
(
    'S10_002',
    '1957 Chevrolet Corvette',
    'Classic Cars',
    '1:18',
    'Motor City Classics',
    'Classic Chevrolet Corvette model',
    75,
    52.00,
    110.00,
    @seed_ts
),
(
    'S20_001',
    'Harley Davidson Motorcycle',
    'Motorcycles',
    '1:12',
    'Highway Models',
    'Classic motorcycle model',
    50,
    35.00,
    80.00,
    @seed_ts
);

-- ---------------------------------------------------------

INSERT IGNORE INTO orders (
    orderNumber,
    orderDate,
    requiredDate,
    shippedDate,
    status,
    comments,
    customerNumber,
    updated_at
)
VALUES
(
    10001,
    DATE_SUB(CURDATE(), INTERVAL 1 DAY),
    DATE_ADD(CURDATE(), INTERVAL 4 DAY),
    DATE_SUB(CURDATE(), INTERVAL 1 DAY),
    'Shipped',
    'Initial sample order',
    101,
    @seed_ts
),
(
    10002,
    DATE_SUB(CURDATE(), INTERVAL 1 DAY),
    DATE_ADD(CURDATE(), INTERVAL 5 DAY),
    NULL,
    'In Process',
    'Awaiting shipment',
    102,
    @seed_ts
),
(
    10003,
    DATE_SUB(CURDATE(), INTERVAL 1 DAY),
    DATE_ADD(CURDATE(), INTERVAL 3 DAY),
    NULL,
    'Resolved',
    'Sample resolved order',
    103,
    @seed_ts
);

-- ---------------------------------------------------------

INSERT IGNORE INTO orderdetails (
    orderNumber,
    productCode,
    quantityOrdered,
    priceEach,
    orderLineNumber,
    updated_at
)
VALUES
(
    10001,
    'S10_001',
    2,
    90.00,
    1,
    @seed_ts
),
(
    10001,
    'S10_002',
    1,
    105.00,
    2,
    @seed_ts
),
(
    10002,
    'S20_001',
    3,
    75.00,
    1,
    @seed_ts
),
(
    10003,
    'S10_001',
    1,
    92.00,
    1,
    @seed_ts
);

-- ---------------------------------------------------------

INSERT IGNORE INTO payments (
    customerNumber,
    checkNumber,
    paymentDate,
    amount,
    updated_at
)
VALUES
(
    101,
    'CHK-1001',
    DATE_SUB(CURDATE(), INTERVAL 1 DAY),
    285.00,
    @seed_ts
),
(
    102,
    'CHK-1002',
    DATE_SUB(CURDATE(), INTERVAL 1 DAY),
    225.00,
    @seed_ts
);