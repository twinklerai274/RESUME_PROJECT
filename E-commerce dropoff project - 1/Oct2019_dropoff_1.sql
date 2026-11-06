CREATE DATABASE ecommerce_dropoff;

USE ecommerce_dropoff;

CREATE TABLE ecommerce_events (
    event_time VARCHAR(50),
    event_type VARCHAR(30),
    product_id BIGINT,
    category_id BIGINT,
    category_code VARCHAR(255),
    brand VARCHAR(100),
    price DECIMAL(10,2),
    user_id BIGINT,
    user_session VARCHAR(100),
    event_date DATE,
    event_hour INT,
    day_of_week VARCHAR(20),
    price_band VARCHAR(20),
    event_datetime DATETIME,
    hour INT,
    time_band VARCHAR(20)
);

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ecommerce_events';

BULK INSERT ecommerce_events           ---importing csv data 
FROM "C:\Users\gk442\OneDrive\Desktop\projects\BA project\ecommerce_october_2019_cleaned.csv"
WITH
(
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDQUOTE = '"',
    TABLOCK
);

SELECT COUNT(*) AS Total_Rows           ---- checking total rows
FROM ecommerce_events;

SELECT TOP 10 *                  
FROM dbo.ecommerce_events;

SELECT                           ---- checking Unique Sessions
    COUNT(*) AS Total_Rows,           ---- checking unique users
    COUNT(DISTINCT user_id) AS Unique_Users,
    COUNT(DISTINCT user_session) AS Unique_Sessions
FROM dbo.ecommerce_events;

/* Step 2 — SQL Data Validation
imported data covers 2019-10-01 from 00:00:00 to 22:43:00, so for the portfolio we have this as October 1, 2019 event data, not a full October month
2.1 Check event types */
SELECT 
    event_type,
    COUNT(*) AS Event_Count
FROM dbo.ecommerce_events
GROUP BY event_type
ORDER BY Event_Count DESC;

-- 2.2 Check NULL values:-
SELECT
    SUM(CASE WHEN event_time IS NULL THEN 1 ELSE 0 END) AS Null_Event_Time,
    SUM(CASE WHEN event_type IS NULL THEN 1 ELSE 0 END) AS Null_Event_Type,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS Null_Product_ID,
    SUM(CASE WHEN category_id IS NULL THEN 1 ELSE 0 END) AS Null_Category_ID,
    SUM(CASE WHEN category_code IS NULL THEN 1 ELSE 0 END) AS Null_Category_Code,
    SUM(CASE WHEN brand IS NULL THEN 1 ELSE 0 END) AS Null_Brand,
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END) AS Null_Price,
    SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) AS Null_User_ID,
    SUM(CASE WHEN user_session IS NULL THEN 1 ELSE 0 END) AS Null_User_Session
FROM dbo.ecommerce_events;

-- 2.3 Check date range:-
SELECT
    MIN(event_datetime) AS First_Event,
    MAX(event_datetime) AS Last_Event
FROM dbo.ecommerce_events;

-- 2.4 Check duplicate rows:-
SELECT
    COUNT(*) AS Duplicate_Rows
FROM
(
    SELECT
        event_datetime,
        event_type,
        product_id,
        category_id,
        category_code,
        brand,
        price,
        user_id,
        user_session,
        COUNT(*) AS Row_Count
    FROM dbo.ecommerce_events
    GROUP BY
        event_datetime,
        event_type,
        product_id,
        category_id,
        category_code,
        brand,
        price,
        user_id,
        user_session
    HAVING COUNT(*) > 1
) AS duplicates;

/*  Build the Session-Level Funnel
Step 1 — Create session funnel table */
USE ecommerce_dropoff;
GO

SELECT
    user_session,

    MAX(CASE 
        WHEN event_type = 'view' THEN 1 
        ELSE 0 
    END) AS Has_View,

    MAX(CASE 
        WHEN event_type = 'cart' THEN 1 
        ELSE 0 
    END) AS Has_Cart,

    MAX(CASE 
        WHEN event_type = 'purchase' THEN 1 
        ELSE 0 
    END) AS Has_Purchase

INTO dbo.session_funnel
FROM dbo.ecommerce_events
GROUP BY user_session;

SELECT TOP 20 *
FROM [dbo].[session_funnel];

--- Step 1 — Count sessions at each funnel stage
SELECT
    COUNT(*) AS Total_Sessions,

    SUM(Has_View) AS View_Sessions,

    SUM(CASE 
        WHEN Has_View = 1 AND Has_Cart = 1 
        THEN 1 ELSE 0 
    END) AS Cart_Sessions,

    SUM(CASE 
        WHEN Has_View = 1 AND Has_Cart = 1 AND Has_Purchase = 1 
        THEN 1 ELSE 0 
    END) AS Purchase_Sessions

FROM [dbo].[session_funnel] ;

--- Step 2 — Calculate Funnel Conversion & Drop-off %:-
SELECT
    View_Sessions,
    Cart_Sessions,
    Purchase_Sessions,

    CAST(Cart_Sessions * 100.0 / NULLIF(View_Sessions, 0) AS DECIMAL(10,2))
        AS View_to_Cart_Conversion,

    CAST(Purchase_Sessions * 100.0 / NULLIF(Cart_Sessions, 0) AS DECIMAL(10,2))
        AS Cart_to_Purchase_Conversion,

    CAST(Purchase_Sessions * 100.0 / NULLIF(View_Sessions, 0) AS DECIMAL(10,2))
        AS View_to_Purchase_Conversion,

    CAST(100 - (Cart_Sessions * 100.0 / NULLIF(View_Sessions, 0)) AS DECIMAL(10,2))
        AS View_to_Cart_Dropoff,

    CAST(100 - (Purchase_Sessions * 100.0 / NULLIF(Cart_Sessions, 0)) AS DECIMAL(10,2))
        AS Cart_to_Purchase_Dropoff,

    CAST(100 - (Purchase_Sessions * 100.0 / NULLIF(View_Sessions, 0)) AS DECIMAL(10,2))
        AS Overall_Dropoff

FROM
(
    SELECT
        SUM(Has_View) AS View_Sessions,

        SUM(CASE
            WHEN Has_View = 1 AND Has_Cart = 1
            THEN 1 ELSE 0
        END) AS Cart_Sessions,

        SUM(CASE
            WHEN Has_View = 1
             AND Has_Cart = 1
             AND Has_Purchase = 1
            THEN 1 ELSE 0
        END) AS Purchase_Sessions

    FROM [dbo].[session_funnel]
) AS Funnel;

/* Important business insight

The major leakage is clearly at the View → Cart stage. Only 4.31% of viewing sessions progressed to cart, while more than half of the cart sessions proceeded to purchase.
This is exactly the kind of finding we want for the BA project:

The primary funnel leakage occurs between product viewing and cart addition, whereas sessions that reach the cart show substantially stronger purchase intent.
*/
--- Category-level Session Funnel:-
-- step 1
USE ecommerce_dropoff;
GO

DROP TABLE IF EXISTS dbo.category_session_funnel;
GO

SELECT
    category_code,
    user_session,

    MAX(CASE 
        WHEN event_type = 'view' THEN 1 
        ELSE 0 
    END) AS Has_View,

    MAX(CASE 
        WHEN event_type = 'cart' THEN 1 
        ELSE 0 
    END) AS Has_Cart,

    MAX(CASE 
        WHEN event_type = 'purchase' THEN 1 
        ELSE 0 
    END) AS Has_Purchase

INTO dbo.category_session_funnel

FROM dbo.ecommerce_events

WHERE category_code IS NOT NULL

GROUP BY
    category_code,
    user_session;
GO

SELECT TOP 20 *              --- step 2
FROM [dbo].[category_session_funnel];

--- Now Step 3 — Category-Level Funnel
SELECT
    category_code,

    SUM(Has_View) AS View_Sessions,

    SUM(CASE
        WHEN Has_View = 1
         AND Has_Cart = 1
        THEN 1
        ELSE 0
    END) AS Cart_Sessions,

    SUM(CASE
        WHEN Has_View = 1
         AND Has_Cart = 1
         AND Has_Purchase = 1
        THEN 1
        ELSE 0
    END) AS Purchase_Sessions

FROM dbo.category_session_funnel

GROUP BY category_code

ORDER BY View_Sessions DESC;

--- Step 4 — Category Conversion & Drop-off Analysis:-
SELECT
    category_code,

    SUM(Has_View) AS View_Sessions,

    SUM(CASE
        WHEN Has_View = 1
         AND Has_Cart = 1
        THEN 1
        ELSE 0
    END) AS Cart_Sessions,

    SUM(CASE
        WHEN Has_View = 1
         AND Has_Cart = 1
         AND Has_Purchase = 1
        THEN 1
        ELSE 0
    END) AS Purchase_Sessions,

    ROUND(
        100.0 *
        SUM(CASE
            WHEN Has_View = 1 AND Has_Cart = 1
            THEN 1 ELSE 0
        END)
        / NULLIF(SUM(Has_View), 0),
        2
    ) AS View_to_Cart_Conversion,

    ROUND(
        100.0 *
        SUM(CASE
            WHEN Has_View = 1
             AND Has_Cart = 1
             AND Has_Purchase = 1
            THEN 1 ELSE 0
        END)
        / NULLIF(
            SUM(CASE
                WHEN Has_View = 1 AND Has_Cart = 1
                THEN 1 ELSE 0
            END), 0
        ),
        2
    ) AS Cart_to_Purchase_Conversion,

    ROUND(
        100.0 *
        SUM(CASE
            WHEN Has_View = 1
             AND Has_Cart = 1
             AND Has_Purchase = 1
            THEN 1 ELSE 0
        END)
        / NULLIF(SUM(Has_View), 0),
        2
    ) AS View_to_Purchase_Conversion

FROM [dbo].[category_session_funnel]

GROUP BY category_code

HAVING SUM(Has_View) >= 500

ORDER BY View_to_Purchase_Conversion DESC;

--- Brand-level Session Funnel(step 1 - create brand_session_funnel)
CREATE TABLE brand_session_funnel
(
    brand VARCHAR(100),
    user_session VARCHAR(100),
    Has_View INT,
    Has_Cart INT,
    Has_Purchase INT
);

-- inserting data from ecommerce_events
INSERT INTO dbo.brand_session_funnel
(
    brand,
    user_session,
    Has_View,
    Has_Cart,
    Has_Purchase
)

SELECT
    brand,
    user_session,

    MAX(CASE
        WHEN event_type = 'view' THEN 1
        ELSE 0
    END) AS Has_View,

    MAX(CASE
        WHEN event_type = 'cart' THEN 1
        ELSE 0
    END) AS Has_Cart,

    MAX(CASE
        WHEN event_type = 'purchase' THEN 1
        ELSE 0
    END) AS Has_Purchase

FROM dbo.ecommerce_events

WHERE brand IS NOT NULL

GROUP BY
    brand,
    user_session;

SELECT TOP 20 *            --- checking that it works
FROM dbo.brand_session_funnel;

---Step 2 — Brand-level conversion analysis
SELECT
    brand,

    SUM(Has_View) AS View_Sessions,

    SUM(CASE
        WHEN Has_View = 1 AND Has_Cart = 1
        THEN 1 ELSE 0
    END) AS Cart_Sessions,

    SUM(CASE
        WHEN Has_View = 1
             AND Has_Cart = 1
             AND Has_Purchase = 1
        THEN 1 ELSE 0
    END) AS Purchase_Sessions,

    CAST(
        SUM(CASE
            WHEN Has_View = 1 AND Has_Cart = 1
            THEN 1 ELSE 0
        END) * 100.0
        / NULLIF(SUM(Has_View), 0)
        AS DECIMAL(10,2)
    ) AS View_to_Cart_Conversion,

    CAST(
        SUM(CASE
            WHEN Has_View = 1
                 AND Has_Cart = 1
                 AND Has_Purchase = 1
            THEN 1 ELSE 0
        END) * 100.0
        / NULLIF(
            SUM(CASE
                WHEN Has_View = 1 AND Has_Cart = 1
                THEN 1 ELSE 0
            END), 0
        )
        AS DECIMAL(10,2)
    ) AS Cart_to_Purchase_Conversion,

    CAST(
        SUM(CASE
            WHEN Has_View = 1
                 AND Has_Cart = 1
                 AND Has_Purchase = 1
            THEN 1 ELSE 0
        END) * 100.0
        / NULLIF(SUM(Has_View), 0)
        AS DECIMAL(10,2)
    ) AS View_to_Purchase_Conversion

FROM [dbo].[brand_session_funnel]

GROUP BY brand

HAVING SUM(Has_View) >= 500

ORDER BY View_to_Purchase_Conversion DESC;

/* Your brand results show, for example:

Samsung: 20,934 view sessions → 1,198 purchase sessions → 5.72% View-to-Purchase
Apple: 19,364 → 894 → 4.62%
Oppo: 1,655 → 72 → 4.35%
Huawei: 5,011 → 176 → 3.51%
Xiaomi: 11,627 → 298 → 2.56% */

--- Price-band funnel analysis:-
-- Does product price influence customer conversion?
CREATE TABLE dbo.price_session_funnel             ---step-1 to create the table
(
    price_band VARCHAR(20),
    user_session VARCHAR(100),
    Has_View INT,
    Has_Cart INT,
    Has_Purchase INT
);

--Step 2 — Populate price_session_funnel
INSERT INTO [dbo].[price_session_funnel]
(
    price_band,
    user_session,
    Has_View,
    Has_Cart,
    Has_Purchase
)
SELECT
    price_band,
    user_session,

    MAX(CASE
        WHEN event_type = 'view' THEN 1
        ELSE 0
    END) AS Has_View,

    MAX(CASE
        WHEN event_type = 'cart' THEN 1
        ELSE 0
    END) AS Has_Cart,

    MAX(CASE
        WHEN event_type = 'purchase' THEN 1
        ELSE 0
    END) AS Has_Purchase

FROM [dbo].[ecommerce_events]
WHERE price_band IS NOT NULL
GROUP BY
    price_band,
    user_session;

SELECT TOP 20 *           ---just checking for price session funnel
FROM dbo.price_session_funnel;
--- Create the Price Band Session Funnel Summary
SELECT
    price_band,

    SUM(Has_View) AS View_Sessions,

    SUM(CASE
        WHEN Has_View = 1
         AND Has_Cart = 1
        THEN 1 ELSE 0
    END) AS Cart_Sessions,

    SUM(CASE
        WHEN Has_View = 1
         AND Has_Cart = 1
         AND Has_Purchase = 1
        THEN 1 ELSE 0
    END) AS Purchase_Sessions,

    CAST(
        SUM(CASE
            WHEN Has_View = 1
             AND Has_Cart = 1
            THEN 1 ELSE 0
        END) * 100.0
        / NULLIF(SUM(Has_View), 0)
        AS DECIMAL(10,2)
    ) AS View_to_Cart_Conversion,

    CAST(
        SUM(CASE
            WHEN Has_View = 1
             AND Has_Cart = 1
             AND Has_Purchase = 1
            THEN 1 ELSE 0
        END) * 100.0
        /
        NULLIF(
            SUM(CASE
                WHEN Has_View = 1
                 AND Has_Cart = 1
                THEN 1 ELSE 0
            END), 0
        )
        AS DECIMAL(10,2)
    ) AS Cart_to_Purchase_Conversion,

    CAST(
        SUM(CASE
            WHEN Has_View = 1
             AND Has_Cart = 1
             AND Has_Purchase = 1
            THEN 1 ELSE 0
        END) * 100.0
        / NULLIF(SUM(Has_View), 0)
        AS DECIMAL(10,2)
    ) AS View_to_Purchase_Conversion

FROM dbo.price_session_funnel

GROUP BY price_band

ORDER BY View_to_Purchase_Conversion DESC;

--- Time-based session funnel:-
-- Which hours have high customer activity but lower conversion?
CREATE TABLE dbo.hour_session_funnel        --step 1 to create table for hour session funnel
(
    event_hour INT,
    user_session VARCHAR(100),
    Has_View INT,
    Has_Cart INT,
    Has_Purchase INT
);

--- step 2 -inserting data from ecommerce event
INSERT INTO dbo.hour_session_funnel
(
    event_hour,
    user_session,
    Has_View,
    Has_Cart,
    Has_Purchase
)
SELECT
    event_hour,
    user_session,

    MAX(CASE
        WHEN event_type = 'view' THEN 1
        ELSE 0
    END) AS Has_View,

    MAX(CASE
        WHEN event_type = 'cart' THEN 1
        ELSE 0
    END) AS Has_Cart,

    MAX(CASE
        WHEN event_type = 'purchase' THEN 1
        ELSE 0
    END) AS Has_Purchase

FROM dbo.ecommerce_events
WHERE event_hour IS NOT NULL
GROUP BY
    event_hour,
    user_session;

SELECT TOP 20 *          --- just checking
FROM dbo.hour_session_funnel
ORDER BY event_hour;

--— step 3-Create the Hourly Session Funnel Summary
SELECT
    event_hour,

    SUM(Has_View) AS View_Sessions,

    SUM(CASE
        WHEN Has_View = 1
         AND Has_Cart = 1
        THEN 1 ELSE 0
    END) AS Cart_Sessions,

    SUM(CASE
        WHEN Has_View = 1
         AND Has_Cart = 1
         AND Has_Purchase = 1
        THEN 1 ELSE 0
    END) AS Purchase_Sessions,

    CAST(
        SUM(CASE
            WHEN Has_View = 1
             AND Has_Cart = 1
            THEN 1 ELSE 0
        END) * 100.0
        / NULLIF(SUM(Has_View), 0)
        AS DECIMAL(10,2)
    ) AS View_to_Cart_Conversion,

    CAST(
        SUM(CASE
            WHEN Has_View = 1
             AND Has_Cart = 1
             AND Has_Purchase = 1
            THEN 1 ELSE 0
        END) * 100.0
        /
        NULLIF(
            SUM(CASE
                WHEN Has_View = 1
                 AND Has_Cart = 1
                THEN 1 ELSE 0
            END), 0
        )
        AS DECIMAL(10,2)
    ) AS Cart_to_Purchase_Conversion,

    CAST(
        SUM(CASE
            WHEN Has_View = 1
             AND Has_Cart = 1
             AND Has_Purchase = 1
            THEN 1 ELSE 0
        END) * 100.0
        / NULLIF(SUM(Has_View), 0)
        AS DECIMAL(10,2)
    ) AS View_to_Purchase_Conversion

FROM [dbo].[hour_session_funnel]

GROUP BY event_hour

ORDER BY event_hour;

---Behavior Analysis:-
--“Do highly engaged sessions have a higher purchase conversion?”
SELECT
    CASE
        WHEN View_Count = 1 THEN '1 View'
        WHEN View_Count BETWEEN 2 AND 3 THEN '2-3 Views'
        WHEN View_Count BETWEEN 4 AND 5 THEN '4-5 Views'
        ELSE '6+ Views'
    END AS View_Band,

    COUNT(*) AS Total_Sessions,

    SUM(Has_Purchase) AS Purchase_Sessions,

    CAST(
        SUM(Has_Purchase) * 100.0
        / NULLIF(COUNT(*), 0)
        AS DECIMAL(10,2)
    ) AS Purchase_Conversion

FROM
(
    SELECT
        user_session,

        COUNT(CASE
            WHEN event_type = 'view' THEN 1
        END) AS View_Count,

        MAX(CASE
            WHEN event_type = 'purchase' THEN 1
            ELSE 0
        END) AS Has_Purchase

    FROM dbo.ecommerce_events

    GROUP BY user_session
) AS Session_Behavior

GROUP BY
    CASE
        WHEN View_Count = 1 THEN '1 View'
        WHEN View_Count BETWEEN 2 AND 3 THEN '2-3 Views'
        WHEN View_Count BETWEEN 4 AND 5 THEN '4-5 Views'
        ELSE '6+ Views'
    END

ORDER BY
    MIN(View_Count);

/* There is a clear difference between single-view sessions and sessions with multiple views:

1-view sessions → 3.32% purchase conversion
2–3 views → 9.29%
4–5 views → 9.33%
6+ views → 9.15%
So, in this sample, sessions with 2 or more product views had substantially higher purchase conversion than single-view sessions.
However, conversion does not continuously increase as views increase. The 4–5 view group is slightly higher than 6+ views.
This is a useful behavioral finding, but we should not yet claim that viewing more products causes higher conversion. */

-- Cart Engagement vs Purchase:-
-- Do sessions that add products to cart have a higher likelihood of purchasing?
SELECT
    CASE
        WHEN Has_Cart = 1 THEN 'Cart Added'
        ELSE 'No Cart'
    END AS Cart_Status,

    COUNT(*) AS Total_Sessions,

    SUM(Has_Purchase) AS Purchase_Sessions,

    CAST(
        SUM(Has_Purchase) * 100.0
        / NULLIF(COUNT(*), 0)
        AS DECIMAL(10,2)
    ) AS Purchase_Conversion

FROM dbo.session_funnel

GROUP BY
    Has_Cart

ORDER BY
    Has_Cart DESC;

/* Key finding

Sessions that added an item to the cart had a 56.77% purchase conversion, compared with 4.78% for sessions without a cart action.

That's a large difference and gives us a strong behavioral insight:

Cart addition is strongly associated with purchase completion in the analyzed sample. */

--- Multiple Product Interaction:-
-- Do sessions interacting with multiple different products have higher purchase conversion?
SELECT
    CASE
        WHEN Product_Count = 1 THEN '1 Product'
        WHEN Product_Count BETWEEN 2 AND 3 THEN '2-3 Products'
        WHEN Product_Count BETWEEN 4 AND 5 THEN '4-5 Products'
        ELSE '6+ Products'
    END AS Product_Interaction_Band,

    COUNT(*) AS Total_Sessions,

    SUM(Has_Purchase) AS Purchase_Sessions,

    CAST(
        SUM(Has_Purchase) * 100.0
        / NULLIF(COUNT(*), 0)
        AS DECIMAL(10,2)
    ) AS Purchase_Conversion

FROM
(
    SELECT
        user_session,

        COUNT(DISTINCT product_id) AS Product_Count,

        MAX(
            CASE
                WHEN event_type = 'purchase' THEN 1
                ELSE 0
            END
        ) AS Has_Purchase

    FROM [dbo].[ecommerce_events]

    GROUP BY user_session
) AS Product_Behavior

GROUP BY
    CASE
        WHEN Product_Count = 1 THEN '1 Product'
        WHEN Product_Count BETWEEN 2 AND 3 THEN '2-3 Products'
        WHEN Product_Count BETWEEN 4 AND 5 THEN '4-5 Products'
        ELSE '6+ Products'
    END

ORDER BY
    MIN(Product_Count);

/* Finding

Interestingly, the pattern is different from the view-count analysis.

As the number of distinct products interacted with increases, purchase conversion decreases in this sample:

7.34% → 7.25% → 6.27% → 5.82%

This suggests that sessions involving many different products may reflect broader browsing or comparison behavior rather than stronger purchase intent.
“Higher product variety within a session was associated with lower purchase conversion in the analyzed sample.” */

--- Purchase Conversion by Session Duration:-
-- Do longer sessions have different purchase conversion rates?
SELECT
    CASE
        WHEN Session_Duration_Minutes < 1 THEN 'Under 1 Min'
        WHEN Session_Duration_Minutes BETWEEN 1 AND 5 THEN '1-5 Min'
        WHEN Session_Duration_Minutes BETWEEN 6 AND 15 THEN '6-15 Min'
        WHEN Session_Duration_Minutes BETWEEN 16 AND 30 THEN '16-30 Min'
        ELSE '30+ Min'
    END AS Duration_Band,

    COUNT(*) AS Total_Sessions,

    SUM(Has_Purchase) AS Purchase_Sessions,

    CAST(
        SUM(Has_Purchase) * 100.0
        / NULLIF(COUNT(*), 0)
        AS DECIMAL(10,2)
    ) AS Purchase_Conversion

FROM
(
    SELECT
        user_session,

        DATEDIFF(
            MINUTE,
            MIN(event_time),
            MAX(event_time)
        ) AS Session_Duration_Minutes,

        MAX(
            CASE
                WHEN event_type = 'purchase' THEN 1
                ELSE 0
            END
        ) AS Has_Purchase

    FROM [dbo].[ecommerce_events]

    GROUP BY user_session
) AS Session_Duration

GROUP BY
    CASE
        WHEN Session_Duration_Minutes < 1 THEN 'Under 1 Min'
        WHEN Session_Duration_Minutes BETWEEN 1 AND 5 THEN '1-5 Min'
        WHEN Session_Duration_Minutes BETWEEN 6 AND 15 THEN '6-15 Min'
        WHEN Session_Duration_Minutes BETWEEN 16 AND 30 THEN '16-30 Min'
        ELSE '30+ Min'
    END

ORDER BY
    MIN(
        CASE
            WHEN Session_Duration_Minutes < 1 THEN 0
            WHEN Session_Duration_Minutes BETWEEN 1 AND 5 THEN 1
            WHEN Session_Duration_Minutes BETWEEN 6 AND 15 THEN 6
            WHEN Session_Duration_Minutes BETWEEN 16 AND 30 THEN 16
            ELSE 31
        END
    );

SELECT
    COUNT(*) AS Total_Rows,
    COUNT(DISTINCT user_session) AS Unique_Sessions,
    SUM(Has_Purchase) AS Purchase_Flag_Total,
    COUNT(DISTINCT CASE 
        WHEN Has_Purchase = 1 THEN user_session 
    END) AS Purchase_Sessions
FROM dbo.session_funnel;