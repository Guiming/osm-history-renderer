-- requires hstore_new, postgis, gist_btree

DROP TABLE IF EXISTS hist_point CASCADE;
CREATE TABLE hist_point (
    id bigint,
    version smallint,
    visible boolean,
    user_id integer,
    user_name text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    tags hstore,
    geom geometry(Point, 3857)
);

DROP TABLE IF EXISTS hist_line CASCADE;
CREATE TABLE hist_line (
    id bigint,
    version smallint,
    minor smallint,
    visible boolean,
    user_id integer,
    user_name text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    tags hstore,
    z_order integer,
    geom geometry(LineString, 3857)
);

DROP TABLE IF EXISTS hist_polygon CASCADE;
CREATE TABLE hist_polygon (
    id bigint,
    version smallint,
    minor smallint,
    visible boolean,
    user_id integer,
    user_name text,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    tags hstore,
    z_order integer,
    area real,
    geom geometry(Polygon, 3857),
    center geometry(Point, 3857)
);

