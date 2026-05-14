/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 * 
 * Автор: 
 * Дата: 
*/

-- Пример фильтрации данных от аномальных значений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
-- Найдем id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
    )
-- Выведем объявления без выбросов:
SELECT *
FROM real_estate.flats
WHERE id IN (SELECT * FROM filtered_id);


-- Задача 1: Время активности объявлений
-- 1. Какие сегменты рынка недвижимости Санкт-Петербурга и городов Ленинградской области 
--    имеют наиболее короткие или длинные сроки активности объявлений?
-- 2. Какие характеристики недвижимости, включая площадь недвижимости, среднюю стоимость квадратного метра, 
--    количество комнат и балконов и другие параметры, влияют на время активности объявлений? 
--    Как эти зависимости варьируют между регионами?
-- 3. Есть ли различия между недвижимостью Санкт-Петербурга и Ленинградской области по полученным результатам?

-- Напишите ваш запрос здесь
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_flats AS (
    SELECT 
        f.id,
        f.total_area,
        f.rooms,
        f.balcony,
        f.ceiling_height,
        f.city_id,  
        f.type_id   
    FROM real_estate.flats f
    WHERE 
        f.total_area < (SELECT total_area_limit FROM limits)
        AND (f.rooms < (SELECT rooms_limit FROM limits) OR f.rooms IS NULL)
        AND (f.balcony < (SELECT balcony_limit FROM limits) OR f.balcony IS NULL)
        AND ((f.ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND f.ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR f.ceiling_height IS NULL)
),
ss AS (
    SELECT 
        a.id,
        a.days_exposition,
        a.last_price,
        f.total_area,
        f.rooms,
        f.balcony,
        c.city,
        CASE 
            WHEN c.city = 'Санкт-Петербург' THEN 'СПб'
            ELSE 'ЛенОбл'
        END AS region_category,
        CASE 
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'Месяц'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'Квартал'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'Полгода'
            WHEN a.days_exposition >= 181 THEN 'Больше полугода'
            ELSE 'Не указано' 
        END AS activity_category,
        a.last_price / NULLIF(f.total_area, 0) AS price_per_sqm
    FROM 
        real_estate.advertisement a
    JOIN 
        filtered_flats f ON a.id = f.id
    JOIN 
        real_estate.city c ON f.city_id = c.city_id  
    JOIN 
        real_estate.type t ON f.type_id = t.type_id  
    WHERE 
        a.days_exposition IS NOT NULL
        AND a.days_exposition > 0
        AND a.last_price > 0
)
SELECT 
    region_category AS "Регион",
    activity_category AS "Период активности",
    COUNT(*) AS "Количество объявлений",
    ROUND(COUNT(*) * 100.0 / NULLIF(SUM(COUNT(*)) OVER (PARTITION BY region_category), 0), 2) AS "Доля в регионе, %",
    ROUND(AVG(price_per_sqm)::numeric, 2) AS "Средняя цена за кв.м, руб",
    ROUND(AVG(total_area)::numeric, 1) AS "Средняя площадь, кв.м",
    ROUND(AVG(rooms), 1) AS "Среднее количество комнат",
    ROUND(AVG(balcony)::numeric, 1) AS "Среднее количество балконов"
FROM 
    ss
GROUP BY 
    activity_category, 
    region_category
ORDER BY 
    region_category, 
    activity_category;


-- Задача 2: Сезонность объявлений
-- 1. В какие месяцы наблюдается наибольшая активность в публикации объявлений о продаже недвижимости? 
--    А в какие — по снятию? Это показывает динамику активности покупателей.
-- 2. Совпадают ли периоды активной публикации объявлений и периоды, 
--    когда происходит повышенная продажа недвижимости (по месяцам снятия объявлений)?
-- 3. Как сезонные колебания влияют на среднюю стоимость квадратного метра и среднюю площадь квартир? 
--    Что можно сказать о зависимости этих параметров от месяца?

-- Напишите ваш запрос здесь
WITH limits AS
(
  SELECT
    PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
    PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
    PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
    PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
    PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
  FROM real_estate.flats
),
filtered_ads AS
(
  SELECT id
  FROM real_estate.flats
  WHERE
    total_area < (SELECT total_area_limit FROM limits)
    AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
    AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
    AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
          AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
ss AS 
(
  SELECT COUNT(*) AS ad_count, 
         EXTRACT(MONTH FROM (first_day_exposition + (days_exposition * INTERVAL '1 day'))) AS ads_remove_month,
         ROUND(AVG(last_price / total_area)::numeric, 2) AS price_per_metre,
         ROUND(AVG(total_area)::numeric, 2) AS avg_area
  FROM real_estate.advertisement
  LEFT JOIN real_estate.flats USING (id)
  WHERE first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31' 
        AND id IN (SELECT * FROM filtered_ads)
  GROUP BY ads_remove_month
),
published_ads AS 
(
  SELECT COUNT(*) AS published_ad_count,
         EXTRACT(MONTH FROM first_day_exposition) AS publish_month,
         ROUND(AVG(last_price / total_area)::numeric, 2) AS published_price_per_metre,
         ROUND(AVG(total_area)::numeric, 2) AS published_avg_area
  FROM real_estate.advertisement
  LEFT JOIN real_estate.flats USING (id)
  WHERE first_day_exposition BETWEEN '2015-01-01' AND '2018-12-31'
        AND id IN (SELECT * FROM filtered_ads)
  GROUP BY publish_month
)
SELECT 
  RANK() OVER (ORDER BY COALESCE(ss.ad_count, 0) DESC) AS rank,
  CASE COALESCE(ss.ads_remove_month, published_ads.publish_month)
    WHEN 1 THEN 'Январь'
    WHEN 2 THEN 'Февраль'
    WHEN 3 THEN 'Март'
    WHEN 4 THEN 'Апрель'
    WHEN 5 THEN 'Май'
    WHEN 6 THEN 'Июнь'
    WHEN 7 THEN 'Июль'
    WHEN 8 THEN 'Август'
    WHEN 9 THEN 'Сентябрь'
    WHEN 10 THEN 'Октябрь'
    WHEN 11 THEN 'Ноябрь'
    WHEN 12 THEN 'Декабрь'
  END AS month,
  COALESCE(ss.ad_count, 0) AS ad_count, 
  ROUND((COALESCE(ss.ad_count, 0) / NULLIF(SUM(ss.ad_count) OVER (), 0)) * 100, 2) AS perc_by_total, 
  COALESCE(ss.price_per_metre, 0) AS price_per_metre, 
  COALESCE(ss.avg_area, 0) AS avg_area,
  COALESCE(published_ads.published_ad_count, 0) AS published_ad_count,
  COALESCE(published_ads.published_price_per_metre, 0) AS published_price_per_metre,
  COALESCE(published_ads.published_avg_area, 0) AS published_avg_area
FROM ss
JOIN published_ads ON ss.ads_remove_month = published_ads.publish_month;




-- Задача 3: Анализ рынка недвижимости Ленобласти
-- 1. В каких населённые пунктах Ленинградской области наиболее активно публикуют объявления о продаже недвижимости?
-- 2. В каких населённых пунктах Ленинградской области — самая высокая доля снятых с публикации объявлений? 
--    Это может указывать на высокую долю продажи недвижимости.
-- 3. Какова средняя стоимость одного квадратного метра и средняя площадь продаваемых квартир в различных населённых пунктах? 
--    Есть ли вариация значений по этим метрикам?
-- 4. Среди выделенных населённых пунктов какие пункты выделяются по продолжительности публикации объявлений? 
--    То есть где недвижимость продаётся быстрее, а где — медленнее.

-- Напишите ваш запрос здесьWITH limits AS (
    WITH limits AS
(
SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),
filtered_flats AS (
    SELECT f.id
    FROM real_estate.flats f
    JOIN limits l ON 
        f.total_area < l.total_area_limit AND
        (f.rooms < l.rooms_limit OR f.rooms IS NULL) AND
        (f.balcony < l.balcony_limit OR f.balcony IS NULL) AND
        ((f.ceiling_height < l.ceiling_height_limit_h AND 
          f.ceiling_height > l.ceiling_height_limit_l) OR f.ceiling_height IS NULL)
),
all_published_flats AS (
    SELECT 
        f.city_id,
        COUNT(*) AS total_published_count
    FROM 
        real_estate.advertisement adv
    JOIN 
        real_estate.flats f ON adv.id = f.id
    WHERE 
        f.id IN (SELECT id FROM filtered_flats)
    GROUP BY 
        f.city_id
),
active_flats AS (
    SELECT 
        f.city_id,
        COUNT(*) AS active_count
    FROM 
        real_estate.advertisement adv
    JOIN 
        real_estate.flats f ON adv.id = f.id
    WHERE 
        adv.days_exposition > 0
        AND f.id IN (SELECT id FROM filtered_flats)
    GROUP BY 
        f.city_id
),
city_stats AS (
    SELECT 
        c.city AS city_name,
        af.active_count AS ad_count,
        ap.total_published_count AS published_count,
        ROUND(AVG(adv.last_price)::numeric, 2) AS average_price,
        ROUND(AVG(adv.last_price / NULLIF(f.total_area, 0))::numeric, 2) AS price_per_metre,
        ROUND(AVG(f.total_area)::numeric, 2) AS avg_area,
        ROUND(AVG(adv.days_exposition)::numeric, 1) AS avg_sale_days,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY adv.days_exposition) AS median_sale_days
    FROM 
        real_estate.advertisement adv
    JOIN 
        real_estate.flats f ON adv.id = f.id
    JOIN 
        real_estate.city c ON f.city_id = c.city_id
    JOIN 
        active_flats af ON c.city_id = af.city_id
    JOIN 
        all_published_flats ap ON c.city_id = ap.city_id
    WHERE 
        c.city != 'Санкт-Петербург'
        AND f.id IN (SELECT id FROM filtered_flats)
        AND adv.days_exposition > 0
    GROUP BY 
        c.city, af.active_count, ap.total_published_count
    HAVING 
        COUNT(*) > 50
)
SELECT 
    city_name,
    ad_count,
    published_count,
    CASE 
        WHEN published_count > 0 THEN ROUND((ad_count::numeric / published_count) , 2)
        ELSE 0 
    END AS removed_count,  
    average_price,
    price_per_metre,
    avg_area,
    ROUND((ad_count::numeric / NULLIF(SUM(ad_count) OVER(), 0)) * 100, 2) AS perc_by_total, 
    avg_sale_days,
    median_sale_days
FROM 
    city_stats
ORDER BY   
    ad_count DESC;