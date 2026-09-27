--- Assignment ---

--- Scenario-Based SQL Assignment — BikeStores ---

--- Task 1 — Build the Sales Detail Dataset

SELECT o.order_id, o.order_date,
       CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
       s.store_name,
       CONCAT(st.first_name, ' ', st.last_name) AS staff_name,
       p.product_name, cat.category_name, b.brand_name,
       oi.quantity, oi.list_price, oi.discount,
       oi.quantity * oi.list_price * (1 - oi.discount) AS net_line_revenue
FROM sales.orders o
JOIN sales.customers c ON o.customer_id = c.customer_id
JOIN sales.stores s ON o.store_id = s.store_id
JOIN sales.staffs st ON o.staff_id = st.staff_id
JOIN sales.order_items oi ON o.order_id = oi.order_id
JOIN production.products p ON oi.product_id = p.product_id
JOIN production.categories cat ON p.category_id = cat.category_id
JOIN production.brands b ON p.brand_id = b.brand_id
WHERE o.order_status = 4
ORDER BY o.order_date DESC;

--- Task 2 — Store Performance Summary (5 marks)

SELECT s.store_name,
       COUNT(DISTINCT o.order_id) AS orders,
       SUM(oi.quantity) AS units_sold,
       SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS net_revenue,
       SUM(oi.quantity * oi.list_price * (1 - oi.discount))
       / COUNT(DISTINCT o.order_id) AS average_order_value
FROM sales.orders o
JOIN sales.stores s ON o.store_id = s.store_id
JOIN sales.order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 4
GROUP BY s.store_name
ORDER BY net_revenue DESC;

--- Task 3 — High-Value Customers

WITH x AS (
    SELECT c.customer_id, CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
           COUNT(DISTINCT o.order_id) AS order_count,
           SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS spending
    FROM sales.customers c
    JOIN sales.orders o ON c.customer_id = o.customer_id
    JOIN sales.order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 4
    GROUP BY c.customer_id, c.first_name, c.last_name
)
SELECT *
FROM x
WHERE spending > (SELECT AVG(spending) FROM x)
ORDER BY spending DESC;

--- Task 4 — Inventory Risk Report

SELECT p.product_name,
       s.store_name,
       st.quantity,
       c.category_name,
       b.brand_name
FROM production.stocks st
JOIN production.products p ON st.product_id = p.product_id
JOIN sales.stores s ON st.store_id = s.store_id
JOIN production.categories c ON p.category_id = c.category_id
JOIN production.brands b ON p.brand_id = b.brand_id
WHERE st.quantity < 5
ORDER BY st.quantity ASC;

--- Task 5 — Top Products Within Each

WITH x AS (
    SELECT cat.category_name, p.product_name,
           SUM(oi.quantity) AS units_sold,
           SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS revenue
    FROM sales.order_items oi
    JOIN sales.orders o ON oi.order_id = o.order_id
    JOIN production.products p ON oi.product_id = p.product_id
    JOIN production.categories cat ON p.category_id = cat.category_id
    WHERE o.order_status = 4
    GROUP BY cat.category_name, p.product_name
),
r AS (
    SELECT *, DENSE_RANK() OVER (
        PARTITION BY category_name ORDER BY revenue DESC
    ) AS position
    FROM x
)
SELECT category_name, product_name, units_sold, revenue, position
FROM r
WHERE position <= 3
ORDER BY category_name, position;

--- Task 6 — Monthly Sales Trend

WITH x AS (
    SELECT
        YEAR(o.order_date) AS year,
        MONTH(o.order_date) AS month,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS revenue
    FROM sales.orders o
    JOIN sales.order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 4
    GROUP BY YEAR(o.order_date), MONTH(o.order_date)
)
SELECT
    year,
    month,
    revenue AS total_net_revenue,
    LAG(revenue) OVER (ORDER BY year, month) AS previous_month_revenue,
    revenue - LAG(revenue) OVER (ORDER BY year, month) AS revenue_change
FROM x
ORDER BY year, month;

--- Task 7 — Reusable Reporting View 

CREATE VIEW sales.vw_customers_sales_summary AS
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    COUNT(DISTINCT o.order_id) AS completed_orders,
    COALESCE(SUM(oi.quantity), 0) AS total_units,
    COALESCE(SUM(oi.quantity * oi.list_price * (1 - oi.discount)), 0) AS total_revenue,
    MAX(o.order_date) AS recent_order_date
FROM sales.customers c
LEFT JOIN sales.orders o
    ON c.customer_id = o.customer_id
    AND o.order_status = 4
LEFT JOIN sales.order_items oi
    ON o.order_id = oi.order_id
GROUP BY c.customer_id, c.first_name, c.last_name;

GO

SELECT * from sales.vw_customers_sales_summary

--- Task 8 — Safe Data Modification

BEGIN TRANSACTION;

UPDATE sales.customers
SET phone = '(999) 555-0101'
WHERE customer_id = 1;

SELECT customer_id, first_name, last_name, phone
FROM sales.customers
WHERE customer_id = 1;

ROLLBACK TRANSACTION;

--- Task 9 — Store Sales Procedure

CREATE PROCEDURE sales.usp_stores_sales_report
    @store_id INT,
    @start_date DATE,
    @end_date DATE
AS
BEGIN
    IF @start_date > @end_date
    BEGIN
        THROW 50001, 'Start date cannot be later than end date.', 1;
    END;

    SELECT
        p.product_name,
        SUM(oi.quantity) AS total_units_sold,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_net_revenue
    FROM sales.orders o
    JOIN sales.order_items oi ON o.order_id = oi.order_id
    JOIN production.products p ON oi.product_id = p.product_id
    WHERE o.store_id = @store_id
      AND o.order_status = 4
      AND o.order_date >= @start_date
      AND o.order_date < DATEADD(DAY, 1, @end_date)
    GROUP BY p.product_name
    ORDER BY total_net_revenue DESC;
END;	

-- Run

EXEC sales.usp_stores_sales_report
    @store_id = 1,
    @start_date = '2017-01-01',
    @end_date = '2017-12-31';

--- Task 10 — Management Insight Query

SELECT
    s.store_name,
    p.product_name,
    SUM(oi.quantity) AS units_sold,
    SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS revenue
FROM sales.orders o
JOIN sales.order_items oi ON o.order_id = oi.order_id
JOIN sales.stores s ON o.store_id = s.store_id
JOIN production.products p ON oi.product_id = p.product_id
WHERE o.order_status = 4
GROUP BY s.store_name, p.product_name
ORDER BY revenue DESC;

-- Business question: Which products generate the most revenue at each store?
-- Measures total units sold and net revenue by store and product.
-- Management can use this to identify strong products and stores.












