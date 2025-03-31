-- requires hstore_new, postgis, gist_btree

DROP TABLE IF EXISTS hist_point CASCADE;
CREATE TABLE IF NOT EXISTS hist_point (
    id bigint,
    version smallint,
    visible boolean,
    user_id integer,
    --user_name text,
    changeset bigint,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    tags hstore,
    geom geometry(Point, 3857)
);

DROP TABLE IF EXISTS hist_line CASCADE;
CREATE TABLE IF NOT EXISTS hist_line (
    id bigint,
    version smallint,
    minor smallint,
    visible boolean,
    user_id integer,
    --user_name text,
    changeset bigint,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    tags hstore,
    z_order integer,
    geom geometry(LineString, 3857)
);

DROP TABLE IF EXISTS hist_polygon CASCADE;
CREATE TABLE IF NOT EXISTS hist_polygon (
    id bigint,
    version smallint,
    minor smallint,
    visible boolean,
    user_id integer,
    --user_name text,
    changeset bigint,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    tags hstore,
    z_order integer,
    area real,
    geom geometry(Polygon, 3857),
    center geometry(Point, 3857)
);

/* GZ */
DROP TABLE IF EXISTS hist_relation CASCADE;
CREATE TABLE IF NOT EXISTS hist_relation (
    id bigint,
    version smallint,
    visible boolean,
    user_id bigint,
    --user_name text,
    changeset bigint,
    valid_from timestamp without time zone,
    valid_to timestamp without time zone,
    tags hstore
);

DROP TABLE IF EXISTS hist_relation_member CASCADE;
CREATE TABLE IF NOT EXISTS hist_relation_member (
    relation_id bigint,
    version smallint,
    member_id bigint,
    member_type text,
    role text --,
    --PRIMARY KEY (relation_id, member_id, version) -- there might be duplicated (relation_id, member_id, version)
);

DROP TABLE IF EXISTS hist_user CASCADE;
CREATE TABLE IF NOT EXISTS hist_user (
    user_id bigint PRIMARY KEY,
    user_name text
);
        

