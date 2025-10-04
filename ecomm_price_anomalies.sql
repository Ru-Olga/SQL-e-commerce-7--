/* =========================================================
   SQL e-commerce: нетто-цены, ценовые аномалии (±10% к 7-дн. минимуму),
   топ-3 регионов по выручке (июнь-2025) и влияние промо.
   СУБД: PostgreSQL
   ========================================================= */

-----------------------------------------------------------------------
-- 1-2-3-4-5) АНОМАЛИИ ЦЕНЫ: отклонение ≥10% от 7-дневного минимума
-----------------------------------------------------------------------


WITH main_table AS (     													        -- Создадим cte для выполнения первоначальных расчётов (цены без налога и в рублях)
			SELECT  order_id,
					to_date(date, 'DD-MM-YY') AS date,     					-- Переведем даты в нужный формат
					seller_id,
					sku,
					region,
					currency,
					fx_rate_to_rub,
					vat_pct,
					price_gross,
					is_test,
					qty,
					is_promo,
					CASE WHEN LEFT(region, 2) != 'RU' 						-- Если регион отличается от Российского, посчитаем price_net_rub с учетом налога в каждом регионе
						 THEN ROUND(((price_gross::NUMERIC / (1 + vat_pct)::numeric)*fx_rate_to_rub)::NUMERIC, 2)
						 ELSE ROUND(((price_gross::NUMERIC / (1 + vat_pct)::numeric)), 2) END AS price_net_rub
			FROM sku
			WHERE order_id NOT IN (SELECT order_id FROM sku WHERE is_test = 1)),  -- Сразу исключим из расчётов строки, где is_test = 1
min_price AS (SELECT  sbq2.*,  												                      -- Создадим cte для расчета минимальной цены за предыдущие 7 дней
					  MIN(min_price) OVER (PARTITION BY sku, seller_id, region ORDER BY date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS min_price_7_days
			  FROM (SELECT  date, sku, seller_id, region,   				              -- Определим минимальную цену на каждую дату в нужной нам связке
			  				MIN(price_net_rub) AS min_price 
			  		FROM main_table GROUP BY date, sku, seller_id, region) AS sbq2 )
SELECT * FROM (
		SELECT	order_id,
				date,
				seller_id,
				sku,
				region,
				price_net_rub,
				min_price,
				min_price_7_days,
				CASE WHEN ABS(((price_net_rub - min_price_7_days)::NUMERIC / NULLIF(min_price_7_days, 0)::NUMERIC)*100) >= 10 
					THEN ROUND(((price_net_rub - min_price_7_days)::NUMERIC / NULLIF(min_price_7_days, 0)::NUMERIC)*100, 2) 
					END AS diff_price  										                      -- Вычислим отклонение от 7-дневного минимума в процентах
		FROM (
			SELECT  mt.*,
					mp.min_price,
					mp.min_price_7_days 
			FROM main_table AS mt
			LEFT JOIN min_price AS mp USING(sku, seller_id, region, date)   -- Заберем минимальные цены на даты в общую таблицу
				) AS sbq3 ) AS sbq4 
				WHERE diff_price IS NOT NULL   								                -- Отберем только строки с аномалиями
ORDER BY sku, seller_id, region, date
;

------------------------------------------------------------
-- 6) ТОП-3 РЕГИОНОВ ПО ВЫРУЧКЕ (ИЮНЬ-2025)
------------------------------------------------------------


WITH main_table AS (     								                    -- Соберем нужные нам данные
			SELECT  to_date(date, 'DD-MM-YY') AS date,      
					region,								
					fx_rate_to_rub,
					vat_pct,
					price_gross,
					is_test,
					qty,
					CASE WHEN LEFT(region, 2) != 'RU' 
						 THEN ROUND(((price_gross::NUMERIC / (1 + vat_pct)::numeric)*fx_rate_to_rub)::NUMERIC, 2)
						 ELSE ROUND(((price_gross::NUMERIC / (1 + vat_pct)::numeric)), 2) END AS price_net_rub
			FROM sku
			WHERE order_id NOT IN (SELECT order_id FROM sku WHERE is_test = 1))
SELECT  region, 
		ROUND(SUM(price_net_rub * qty), 2) AS revenue           -- Посчитаем выручку
FROM main_table AS mt
WHERE date BETWEEN '2025-06-01' AND '2025-06-30'            -- Отберем данные нужного нам диапазона времени
GROUP BY region 
ORDER BY revenue DESC                                       -- Отсортируем регионы по убыванию выручки
LIMIT 3    													                        -- Оставим ТОП-3
;


---------------------------------------------------------------
-- 7) ВЛИЯНИЕ ПРОМО (ИЮНЬ-2025): promo vs non-promo
---------------------------------------------------------------

WITH main_table AS (     				-- Соберем нужные нам данные
			SELECT  to_date(date, 'DD-MM-YY') AS date,
					region,
					qty,
					is_promo
			FROM sku
			WHERE order_id NOT IN (SELECT order_id FROM sku WHERE is_test = 1))
SELECT  region,     					-- Посчитаем количество проданных товаров по промо-акции и без нее
		SUM(CASE WHEN is_promo = 1 THEN qty END) AS promo,
		SUM(CASE WHEN is_promo = 0 THEN qty END) AS no_promo
FROM main_table
WHERE date BETWEEN '2025-06-01' AND '2025-06-30'
GROUP BY region    						-- Сгруппируем по регионам
ORDER BY region


/* =========================================================
   КРАТКИЕ ВЫВОДЫ 
   -------------------------------------------------------
   • Ценовые аномалии: отображаются строки с отклонением цены ≥10% к 7-дн. минимуму.
   • Топ-3 регионов (июнь-2025): EU-DE, GB-LON, AU-SYD.
   • Влияние промо: продажи в промо примерно x2 выше, чем в non-promo (июнь-2025). Значит, промо-акция повлияла.
   ========================================================= */
