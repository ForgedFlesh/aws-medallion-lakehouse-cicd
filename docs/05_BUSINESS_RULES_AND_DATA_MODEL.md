# 5. Business rules and dimensional model

## Source business keys

- customers: `customerNumber`
- products: `productCode`
- orders: `orderNumber`
- order details: `(orderNumber, orderLineNumber)`
- payments: `(customerNumber, checkNumber)`
- ratings event: `(customerNumber, productCode, ratingTimestamp)`
- current rating: `(customerNumber, productCode)`

## Curated rules

1. Every business key must be present and castable.
2. `quantityOrdered > 0`.
3. `priceEach`, payment amount, buy price and MSRP cannot be negative.
4. Product stock cannot be negative.
5. Product rating must be an integer from 1 through 5.
6. Rating customer and product must exist in curated master data.
7. Duplicate source keys in one batch are removed before publication.
8. The current ratings table retains the latest rating by event timestamp and
   ingest timestamp.

## Fact table grain

### `fact_order_items`

One row per `(orderNumber, orderLineNumber)`.

Measures:

- quantity ordered
- price each
- gross amount

Foreign keys:

- customer number
- product code
- order date key

### `fact_product_ratings`

One row per rating event. The timestamp is part of the identity so a customer's
rating history can be analysed.

Measure:

- product rating

## Dimensions

### `dim_customers`

Customer name, contact, geography and credit limit. Current implementation is a
Type 1 current-state dimension.

### `dim_products`

Product name, line, vendor, stock, buy price and MSRP.

### `dim_date`

Calendar fields derived from order dates for consistent month/quarter/year
analysis.

## Why this is a star schema

The facts hold events and measures. Dimensions hold descriptive attributes.
Reporting queries aggregate facts and group/filter through dimensions without
joining the normalized eight-table source model every time.
