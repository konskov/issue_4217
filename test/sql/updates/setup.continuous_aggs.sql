-- This file and its contents are licensed under the Apache License 2.0.
-- Please see the included NOTICE for copyright information and
-- LICENSE-APACHE for a copy of the license.

CREATE TYPE custom_type AS (high int, low int);

CREATE TABLE conditions_before (
      timec       TIMESTAMPTZ       NOT NULL,
      location    TEXT              NOT NULL,
      temperature DOUBLE PRECISION  NULL,
      humidity    DOUBLE PRECISION  NULL,
      lowp        double precision NULL,
      highp       double precision null,
      allnull     double precision null,
      highlow     custom_type null,
      bit_int     smallint,
      good_life   boolean
    );

SELECT table_name FROM create_hypertable( 'conditions_before', 'timec');

INSERT INTO conditions_before
SELECT generate_series('2018-12-01 00:00'::timestamp, '2018-12-31 00:00'::timestamp, '1 day'), 'POR', 55, 75, 40, 70, NULL, (1,2)::custom_type, 2, true;
INSERT INTO conditions_before
SELECT generate_series('2018-11-01 00:00'::timestamp, '2018-12-31 00:00'::timestamp, '1 day'), 'NYC', 35, 45, 50, 40, NULL, (3,4)::custom_type, 4, false;
INSERT INTO conditions_before
SELECT generate_series('2018-11-01 00:00'::timestamp, '2018-12-15 00:00'::timestamp, '1 day'), 'LA', 73, 55, NULL, 28, NULL, NULL, 8, true;

DO LANGUAGE PLPGSQL $$
DECLARE
  ts_version TEXT;
BEGIN
  SELECT extversion INTO ts_version FROM pg_extension WHERE extname = 'timescaledb';
  IF ts_version < '2.0.0' THEN
    CREATE VIEW mat_before
    WITH ( timescaledb.continuous, timescaledb.refresh_lag='-30 day', timescaledb.max_interval_per_job ='1000 day')
    AS
      SELECT time_bucket('1week', timec) as bucket,
	location,
	min(allnull) as min_allnull,
	max(temperature) as max_temp,
	sum(temperature)+sum(humidity) as agg_sum_expr,
	avg(humidity) AS avg_humidity,
	stddev(humidity),
	bit_and(bit_int),
	bit_or(bit_int),
	bool_and(good_life),
	every(temperature > 0),
	bool_or(good_life),
	count(*) as count_rows,
	count(temperature) as count_temp,
	count(allnull) as count_zero,
	corr(temperature, humidity),
	covar_pop(temperature, humidity),
	covar_samp(temperature, humidity),
	regr_avgx(temperature, humidity),
	regr_avgy(temperature, humidity),
	regr_count(temperature, humidity),
	regr_intercept(temperature, humidity),
	regr_r2(temperature, humidity),
	regr_slope(temperature, humidity),
	regr_sxx(temperature, humidity),
	regr_sxy(temperature, humidity),
	round(regr_syy(temperature, humidity)) as regr_syy,
	stddev(temperature) as stddev_temp,
	round(stddev_pop(temperature)) as stddev_pop,
	stddev_samp(temperature),
	round(variance(temperature)) as variance,
	round(var_pop(temperature)) as var_pop,
	round(var_samp(temperature)) as var_samp,
	last(temperature, timec) as last_temp,
	last(highlow, timec) as last_hl,
	first(highlow, timec) as first_hl,
	histogram(temperature, 0, 100, 5)
      FROM conditions_before
      GROUP BY bucket, location
      HAVING min(location) >= 'NYC' and avg(temperature) > 2;
  ELSE
    CREATE MATERIALIZED VIEW IF NOT EXISTS mat_before
    WITH ( timescaledb.continuous)
    AS
      SELECT time_bucket('1week', timec) as bucket,
	location,
	min(allnull) as min_allnull,
	max(temperature) as max_temp,
	sum(temperature)+sum(humidity) as agg_sum_expr,
	avg(humidity) AS avg_humidity,
	stddev(humidity),
	bit_and(bit_int),
	bit_or(bit_int),
	bool_and(good_life),
	every(temperature > 0),
	bool_or(good_life),
	count(*) as count_rows,
	count(temperature) as count_temp,
	count(allnull) as count_zero,
	corr(temperature, humidity),
	covar_pop(temperature, humidity),
	covar_samp(temperature, humidity),
	regr_avgx(temperature, humidity),
	regr_avgy(temperature, humidity),
	regr_count(temperature, humidity),
	regr_intercept(temperature, humidity),
	regr_r2(temperature, humidity),
	regr_slope(temperature, humidity),
	regr_sxx(temperature, humidity),
	regr_sxy(temperature, humidity),
	round(regr_syy(temperature, humidity)) as regr_syy,
	stddev(temperature) as stddev_temp,
	round(stddev_pop(temperature)) as stddev_pop,
	stddev_samp(temperature),
	round(variance(temperature)) as variance,
	round(var_pop(temperature)) as var_pop,
	round(var_samp(temperature)) as var_samp,
	last(temperature, timec) as last_temp,
	last(highlow, timec) as last_hl,
	first(highlow, timec) as first_hl,
	histogram(temperature, 0, 100, 5)
      FROM conditions_before
      GROUP BY bucket, location
      HAVING min(location) >= 'NYC' and avg(temperature) > 2 WITH NO DATA;
    PERFORM add_continuous_aggregate_policy('mat_before', NULL, '-30 days'::interval, '336 h');

  END IF;

  IF ts_version >= '2.0.0' THEN
    ALTER MATERIALIZED VIEW mat_before SET (timescaledb.materialized_only=true);
  ELSIF ts_version >= '1.7.0' THEN
    ALTER VIEW mat_before SET (timescaledb.materialized_only=true);
  END IF;
END $$;

GRANT SELECT ON mat_before TO cagg_user WITH GRANT OPTION;

-- have to use psql conditional here because the procedure call can't be in transaction
SELECT extversion < '2.0.0' AS has_refresh_mat_view from pg_extension WHERE extname = 'timescaledb' \gset
\if :has_refresh_mat_view
REFRESH MATERIALIZED VIEW mat_before;
\else
CALL refresh_continuous_aggregate('mat_before',NULL,NULL);
\endif

