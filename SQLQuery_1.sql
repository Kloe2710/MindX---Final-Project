SELECT *
FROM superstore_processed

SELECT CUSTOMER_ID,
DATEDIFF(DAY,MAX(Order_Date),(SELECT MAX(Order_Date) FROM superstore_processed)) AS "RECENCY",
COUNT(Order_ID) AS "FREQUENCY",
SUM(Sales) AS "MONETARY"
INTO CUSTOMER_RFM
FROM superstore_processed
GROUP BY Customer_ID

SELECT CUSTOMER_ID, RECENCY 
into Recency
FROM CUSTOMER_RFM

SELECT * FROM CUSTOMER_RFM

-- recency rank: quartile 1 - đơn hàng xa nhất nhất, quart 5 - gần nhất
with r as 
(
SELECT ROW_NUMBER() OVER (ORDER BY Recency DESC) AS RowID,*
FROM Recency
)
SELECT RowID, NTILE(5) OVER (ORDER BY RowID ASC) AS R_QUARTILE,Customer_id, Recency
into recency_rank
FROM r

-- frequency
with f as 
(
SELECT ROW_NUMBER() OVER (ORDER BY frequency ASC) AS RowID,*
FROM CUSTOMER_RFM
)
SELECT RowID, NTILE(5) OVER (ORDER BY RowID ASC) AS F_QUARTILE,Customer_id, frequency
into frequnecy_rank
FROM f

-- monetary
with m as 
(
SELECT ROW_NUMBER() OVER (ORDER BY monetary ASC) AS RowID,*
FROM CUSTOMER_RFM
)
SELECT RowID, NTILE(5) OVER (ORDER BY RowID ASC) AS M_QUARTILE,Customer_id, monetary
into monetary_rank
FROM m

SELECT * from frequnecy_rank
SELECT R_QUARTILE, COUNT(customer_id), avg(recency) from recency_rank GROUP BY R_QUARTILE ORDER BY R_QUARTILE DESC
SELECT * from monetary_rank
SELECT * from customer_rfm_rank

-- customer rfm rank
SELECT r.customer_id, R_QUARTILE, f.F_QUARTILE,m.M_QUARTILE
into customer_rfm_rank
FROM recency_rank r
JOIN (select customer_id, f_quartile from frequnecy_rank) f on r.customer_id = f.customer_id
JOIN (select customer_id, m_quartile from monetary_rank) m on r.customer_id = m.customer_id



SELECT customer_id, r_quartile, f_quartile, m_quartile,
       CASE
           WHEN R_QUARTILE = 5 AND F_QUARTILE = 5 AND M_QUARTILE IN (5, 4) THEN 'Champions' -- thường xuyên, gần đây và chi tiêu nhiều nhất
           WHEN R_QUARTILE IN (3,4, 5) AND F_QUARTILE IN (3,4, 5) AND M_QUARTILE IN (3,4, 5) THEN 'Loyal Customers'  -- thường xuyên, chi tiêu tầm trung và mua gần đây
           WHEN R_QUARTILE IN (3,4, 5) AND F_QUARTILE IN (3, 4, 5) AND M_QUARTILE IN (1, 2, 3) THEN 'Potential Loyalists' -- gần đây, thường xuyên, chưa chi tiêu lớn 
           WHEN R_QUARTILE = 5 AND F_QUARTILE IN (1, 2) AND M_QUARTILE IN (1, 2) THEN 'Recent Customers' -- gần đây, có quay lại
           WHEN R_QUARTILE IN (3, 4, 5) AND F_QUARTILE IN (1, 2,3) AND M_QUARTILE IN (3, 4, 5) THEN 'Promising' -- chi tiêu tốt, gần đây nhưng chưa mua nhiều lần
           WHEN R_QUARTILE IN (1,2) AND F_QUARTILE IN (3,4,5) AND M_QUARTILE IN (3, 4,5) THEN 'Customers Needing Attention' -- chi tiêu tốt, gần đây, lâu chưa quay lại
           ELSE 'Churn' -- 225 days - 3 năm chưa có đơn , lượt mua và giá trị đơn hàng thấp nhất
       END AS RFM_SEGMENT
into customer_rfm_segment     
FROM customer_rfm_rank


SELECT rfm_segment, count(customer_id) AS cus_qty, AVG(R_QUARTILE) AS avg_r_rank, AVG(F_QUARTILE) AS avg_f_rank, AVG(M_QUARTILE) AS avg_m_rank
FROM customer_rfm_segment
GROUP by rfm_segment

-- TB mỗi quartile của recency
SELECT R_QUARTILE,min(Recency) as min_days, MAX(Recency) as max_days
FROM recency_rank 
GROUP BY R_QUARTILE
ORDER BY R_QUARTILE DESC

-- TB mỗi quartile của frequency
SELECT F_QUARTILE,min(frequency) as min_frequency,max(frequency) as max_frequency
FROM frequnecy_rank 
GROUP BY F_QUARTILE
ORDER BY F_QUARTILE DESC

-- TB mỗi quartile của monetary
SELECT M_QUARTILE,round(min(monetary),2) as min_spending, round(max(monetary),2) as max_spending
FROM monetary_rank 
GROUP BY M_QUARTILE
ORDER BY M_QUARTILE DESC

SELECT * from frequnecy_rank
-- Cohort # of retain user
-- 1. Tìm order month của mỗi order
WITH A AS (
    SELECT Order_ID, Order_Date, Customer_ID, Sales, FORMAT(Order_Date,'yyyy-MM-01') ORDER_MONTH
    FROM superstore_processed
),
-- 2. Tìm cohort month của mỗi user (tháng đầu tiên phát sinh order)
B AS (
    SELECT Customer_ID,
    FORMAT(MIN(Order_Date),'yyyy-MM-01') COHORT_MONTH
    FROM superstore_processed
    GROUP BY CUSTOMER_ID
),
-- 3. Join order month (nhiều dòng) với cohort month bằng customer id -> bảng có thông tin KH gồm cohort month (tháng onboard) và order month (các tháng phát sinh order)
-- 3.1 tìm cohort index = số tháng từ cohort month tới order month 
C AS (
    SELECT A.*, B.COHORT_MONTH, DATEDIFF(MONTH,B.COHORT_MONTH,A.ORDER_MONTH) AS COHORT_INDEX
    FROM A JOIN B ON A.CUSTOMER_ID = B.CUSTOMER_ID
)
-- 4. Đếm số KH có cùng cohort month, cùng order month, cùng cohort index
SELECT COHORT_MONTH, ORDER_MONTH, COHORT_INDEX, COUNT(DISTINCT CUSTOMER_ID) AS CUSTOMER_QTY
FROM C
GROUP BY COHORT_MONTH, ORDER_MONTH, COHORT_INDEX


-- Sales đem về từ retain customer
WITH A AS (
    SELECT Order_ID, Order_Date, Customer_ID, Sales, FORMAT(Order_Date,'yyyy-MM-01') ORDER_MONTH
    FROM superstore_processed
),

B AS (
    SELECT Customer_ID,
    FORMAT(MIN(Order_Date),'yyyy-MM-01') COHORT_MONTH
    FROM superstore_processed
    GROUP BY CUSTOMER_ID
),
C AS (
    SELECT A.*, B.COHORT_MONTH, DATEDIFF(MONTH,B.COHORT_MONTH,A.ORDER_MONTH) AS COHORT_INDEX
    FROM A JOIN B ON A.CUSTOMER_ID = B.CUSTOMER_ID
)
SELECT COHORT_MONTH, ORDER_MONTH, COHORT_INDEX, sum(sales) AS CUSTOMER_Sales
FROM C
GROUP BY COHORT_MONTH, ORDER_MONTH, COHORT_INDEX

select * from COHORT_TABLe_sales