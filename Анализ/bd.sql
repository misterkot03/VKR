-- =========================
--  AGRUS: demo database
--  PostgreSQL 13+ 
-- =========================

-- Чистый старт: отдельная схема
DROP SCHEMA IF EXISTS agrus CASCADE;
CREATE SCHEMA agrus;
SET search_path = agrus, public;

-- Справочники/типы
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'order_status') THEN
    CREATE TYPE order_status AS ENUM ('NEW','ACCEPTED','DONE','REJECTED','CANCELLED');
  END IF;
END$$;

-- Пользователи системы (мастер/клиент)
CREATE TABLE users (
  id            SERIAL PRIMARY KEY,
  role          TEXT NOT NULL CHECK (role IN ('master','client')),
  name          TEXT NOT NULL,
  email         TEXT NOT NULL UNIQUE,
  pass_salt     TEXT,
  pass_hash     TEXT
);

-- Сессии (для примера: хранение серверных токенов)
CREATE TABLE sessions (
  token         VARCHAR(64) PRIMARY KEY,
  user_id       INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at    TIMESTAMPTZ NOT NULL
);

-- Категории услуг
CREATE TABLE categories (
  id            SERIAL PRIMARY KEY,
  name          TEXT NOT NULL UNIQUE
);

-- Услуги мастеров
CREATE TABLE services (
  id            SERIAL PRIMARY KEY,
  master_id     INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category_id   INT NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
  title         TEXT NOT NULL,
  description   TEXT DEFAULT '',
  price         NUMERIC(12,2) NOT NULL DEFAULT 0
);
CREATE INDEX services_by_cat ON services(category_id);
CREATE INDEX services_by_master ON services(master_id);

-- Заказы
CREATE TABLE orders (
  id               SERIAL PRIMARY KEY,
  service_id       INT NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  master_id        INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_id        INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  comment          TEXT DEFAULT '',
  desired_datetime TIMESTAMPTZ NOT NULL,
  status           order_status NOT NULL DEFAULT 'NEW',
  status_date      TIMESTAMPTZ NOT NULL DEFAULT now(),
  rejection_reason TEXT
);
CREATE INDEX orders_master_dt_status ON orders(master_id, desired_datetime, status);
CREATE INDEX orders_client_dt_status ON orders(client_id, desired_datetime, status);

-- Расписание мастера
-- week_template: JSONB вида {"1":[["09:00","13:00"],["14:00","18:00"]], "0":[]}
CREATE TABLE availability (
  master_id     INT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  slot_minutes  INT NOT NULL CHECK (slot_minutes IN (15,20,30,45,60,90,120)),
  week_template JSONB NOT NULL
);

-- Исключения по датам (праздники/особые интервалы)
-- ranges: JSONB вида [["10:00","16:00"]]   или пустой [] => выходной
CREATE TABLE availability_exceptions (
  master_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day       DATE NOT NULL,
  ranges    JSONB NOT NULL,
  PRIMARY KEY (master_id, day)
);

-- =========================
-- Демо-данные (максимально близко к нашему json)
-- =========================
-- Пользователи
INSERT INTO users (id, role, name, email) VALUES
 (1,'master','Иван Мастер','master@agrus.test'),
 (2,'client','Пётр Клиент','client@agrus.test'),
 (3,'client','Жилкин Дмитрий Анатольевич','zhilkin142510@gmail.com'),
 (4,'master','Иван','master@mail.ru'),
 (5,'client','Иван','client@mail.ru'),
 (6,'client','Дмитрий','client2@mail.ru'),
 (7,'client','Елена','client1@mail.ru');

-- Категории
INSERT INTO categories (id,name) VALUES
 (1,'Ремонт техники'),
 (2,'Уборка и клининг'),
 (3,'Сантехника'),
 (4,'Электрика'),
 (5,'Сборка мебели');

-- Услуги
INSERT INTO services (id,master_id,category_id,title,description,price) VALUES
 (1,1,1,'Ремонт стиральной машины','Диагностика и ремонт на дому.',2500),
 (2,1,2,'Генеральная уборка 1к квартиры','Инвентарь включён.',3500),
 (3,4,1,'Починка крана','Починка, замена, обслуживание кранов любых видов и размеров',500),
 (4,4,3,'Установка смесителя','Снятие старого и монтаж нового смесителя. Подключение шлангов, проверка герметичности.',1200),
 (5,1,3,'Чистка сифона и устранение засора','Бережная прочистка сифона и труб без химии. Даём рекомендации по профилактике.',900),
 (6,1,4,'Замена розетки','Диагностика, безопасная замена, проверка контактов. Материалы могут оплачиватьcя отдельно.',700),
 (7,4,4,'Подключение люстры','Сборка, монтаж и подключение люстры до 12 кг, настройка выключателя.',1500),
 (8,1,5,'Сборка кухонного стола','Сборка по инструкции, проверка устойчивости и фиксации крепежа.',1600),
 (9,4,5,'Сборка шкафа-купе','Профессиональная сборка шкафов-купе, регулировка дверей, навеска полок.',4500),
 (10,1,2,'Поддерживающая уборка','Лёгкая уборка: пыль, полы, санузел. Свои чистящие средства.',1500),
 (11,4,1,'Установка смесителя','Установка',1000);

-- Базовое расписание мастеров (1 и 4)
INSERT INTO availability (master_id, slot_minutes, week_template) VALUES
 (1,30,'{
   "1":[["09:00","13:00"],["14:00","18:00"]],
   "2":[["09:00","13:00"],["14:00","18:00"]],
   "3":[["09:00","13:00"],["14:00","18:00"]],
   "4":[["09:00","13:00"],["14:00","18:00"]],
   "5":[["10:00","16:00"]],
   "6":[["10:00","14:00"]],
   "0":[]
 }'::jsonb),
 (4,30,'{
   "1":[["09:00","13:00"],["14:00","18:00"]],
   "2":[["09:00","13:00"],["14:00","18:00"]],
   "3":[["09:00","13:00"],["14:00","18:00"]],
   "4":[["09:00","13:00"],["14:00","18:00"]],
   "5":[["10:00","16:00"]],
   "6":[["10:00","14:00"]],
   "0":[]
 }'::jsonb);

-- Пара удобных дат вокруг текущей: прошлые/будущие
-- (для графиков и KPI будет что показать)
WITH d AS (
  SELECT 
    (date_trunc('day', now()) - interval '28 day')::timestamptz AS start_dt,
    (date_trunc('day', now()) + interval '14 day')::timestamptz AS end_dt
)
INSERT INTO orders (service_id,master_id,client_id,comment,desired_datetime,status,status_date,rejection_reason)
VALUES
  -- мастер #4 (тот, под которым мы сейчас работаем)
  (3,4,7,'Течёт у раковины', (SELECT start_dt   FROM d) + interval '09:00', 'DONE',      now() - interval '20 day', NULL),
  (4,4,7,'Шумит смеситель', (SELECT start_dt   FROM d) + interval '12:00', 'REJECTED',  now() - interval '19 day', 'Нет нужных запчастей'),
  (7,4,7,'Подключить люстру',(SELECT start_dt   FROM d) + interval '15 day' + interval '10:00','ACCEPTED', now() - interval '2 day', NULL),
  (9,4,7,'Шкаф из IKEA',     (SELECT start_dt   FROM d) + interval '22 day' + interval '17:00','NEW',      now() - interval '1 day',  NULL),
  (11,4,7,'Смеситель на кухню',(SELECT end_dt   FROM d) - interval '7 day' + interval '11:00','CANCELLED', now() - interval '7 day',  NULL),

  -- мастер #1 для разнообразия
  (1,1,2,'Сломался насос',   (SELECT start_dt   FROM d) + interval '10:00','NEW',       now() - interval '25 day', NULL),
  (2,1,7,'Генеральная уборка',(SELECT start_dt  FROM d) + interval '6 day' + interval '13:30','DONE',     now() - interval '6 day',  NULL),
  (6,1,7,'Замена розетки',   (SELECT start_dt   FROM d) + interval '12 day' + interval '09:30','ACCEPTED', now() - interval '3 day',  NULL),
  (10,1,7,'Поддержка чистоты',(SELECT end_dt    FROM d) - interval '2 day' + interval '16:00','NEW',      now() - interval '1 day',  NULL);

-- =========================
-- Полезные представления (для отчётов/скринов)
-- =========================

-- Разбивка заказов по статусам для мастера
CREATE OR REPLACE VIEW v_orders_kpi_by_master AS
SELECT
  o.master_id,
  COUNT(*)                                   AS total,
  COUNT(*) FILTER (WHERE o.status='NEW')     AS new_cnt,
  COUNT(*) FILTER (WHERE o.status='ACCEPTED')AS accepted_cnt,
  COUNT(*) FILTER (WHERE o.status='DONE')    AS done_cnt,
  COUNT(*) FILTER (WHERE o.status='REJECTED')AS rejected_cnt,
  COUNT(*) FILTER (WHERE o.status='CANCELLED')AS cancelled_cnt
FROM orders o
GROUP BY o.master_id;

-- Выручка по дням: потенциальная (все заявки) и фактическая (DONE)
CREATE OR REPLACE VIEW v_revenue_by_day AS
SELECT
  o.master_id,
  date_trunc('day', o.desired_datetime) AS day,
  SUM(s.price)                          AS potential_amount,
  SUM(s.price) FILTER (WHERE o.status='DONE') AS done_amount
FROM orders o
JOIN services s ON s.id = o.service_id
GROUP BY o.master_id, date_trunc('day', o.desired_datetime)
ORDER BY day;

-- Быстрая проверка: KPI по текущему мастеру (id = 4)
-- SELECT * FROM v_orders_kpi_by_master WHERE master_id = 4;
-- SELECT * FROM v_revenue_by_day WHERE master_id = 4 ORDER BY day;
