--ALTER TABLE hist_point ADD PRIMARY KEY (id, version);
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index
        JOIN pg_class ON pg_index.indrelid = pg_class.oid
        WHERE pg_class.relname = 'hist_point'
        AND pg_index.indisprimary
    ) THEN
        ALTER TABLE hist_point ADD PRIMARY KEY (id, version);
    END IF;
END $$;
--/*
CREATE INDEX IF NOT EXISTS hist_point_geom ON hist_point USING GIST (geom);
CREATE INDEX IF NOT EXISTS hist_point_time_index ON hist_point USING BTREE (valid_from, valid_to);
CREATE INDEX IF NOT EXISTS hist_point_validfrom ON hist_point USING BTREE (valid_from);
CREATE INDEX IF NOT EXISTS hist_point_validto ON hist_point USING BTREE (valid_to);
CREATE INDEX IF NOT EXISTS hist_point_uid ON hist_point (user_id);
CREATE INDEX IF NOT EXISTS hist_point_changeset ON hist_point USING BTREE (changeset);
--*/

--ALTER TABLE hist_line ADD PRIMARY KEY (id, version, minor);
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index
        JOIN pg_class ON pg_index.indrelid = pg_class.oid
        WHERE pg_class.relname = 'hist_line'
        AND pg_index.indisprimary
    ) THEN
        ALTER TABLE hist_line ADD PRIMARY KEY (id, version, minor);
    END IF;
END $$;
---/*
CREATE INDEX IF NOT EXISTS hist_line_geom ON hist_line USING GIST (geom);
CREATE INDEX IF NOT EXISTS hist_line_time_index ON hist_line USING BTREE (valid_from, valid_to);
CREATE INDEX IF NOT EXISTS hist_line_validfrom ON hist_line USING BTREE (valid_from);
CREATE INDEX IF NOT EXISTS hist_line_validto ON hist_line USING BTREE (valid_to);
CREATE INDEX IF NOT EXISTS hist_line_uid ON hist_line (user_id);
CREATE INDEX IF NOT EXISTS hist_line_changeset ON hist_line USING BTREE (changeset);
--*/

--ALTER TABLE hist_polygon ADD PRIMARY KEY (id, version, minor);
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index
        JOIN pg_class ON pg_index.indrelid = pg_class.oid
        WHERE pg_class.relname = 'hist_polygon'
        AND pg_index.indisprimary
    ) THEN
        ALTER TABLE hist_polygon ADD PRIMARY KEY (id, version, minor);
    END IF;
END $$;
--/*
CREATE INDEX IF NOT EXISTS hist_polygon_geom ON hist_polygon USING GIST (geom);
CREATE INDEX IF NOT EXISTS hist_polygon_time_index ON hist_polygon USING BTREE (valid_from, valid_to);
CREATE INDEX IF NOT EXISTS hist_polygon_validfrom ON hist_polygon USING BTREE (valid_from);
CREATE INDEX IF NOT EXISTS hist_polygon_validto ON hist_polygon USING BTREE (valid_to);
CREATE INDEX IF NOT EXISTS hist_polygon_uid ON hist_polygon (user_id);
CREATE INDEX IF NOT EXISTS hist_polygon_changeset ON hist_polygon USING BTREE (changeset);
--*/


--ALTER TABLE hist_relation ADD PRIMARY KEY (id, version);
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index
        JOIN pg_class ON pg_index.indrelid = pg_class.oid
        WHERE pg_class.relname = 'hist_relation'
        AND pg_index.indisprimary
    ) THEN
        ALTER TABLE hist_relation ADD PRIMARY KEY (id, version);
    END IF;
END $$;
--/*
CREATE INDEX IF NOT EXISTS hist_relation_time_index ON hist_relation USING BTREE (valid_from, valid_to);
CREATE INDEX IF NOT EXISTS hist_relation_validfrom ON hist_relation USING BTREE (valid_from);
CREATE INDEX IF NOT EXISTS hist_relation_validto ON hist_relation USING BTREE (valid_to);
CREATE INDEX IF NOT EXISTS hist_relation_uid ON hist_relation (user_id);
CREATE INDEX IF NOT EXISTS hist_relation_changeset ON hist_relation USING BTREE (changeset);


--ALTER TABLE hist_relation_member ADD PRIMARY KEY (relaton_id, member_id, version);
/*
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_index
        JOIN pg_class ON pg_index.indrelid = pg_class.oid
        WHERE pg_class.relname = 'hist_relation_member'
        AND pg_index.indisprimary
    ) THEN
        ALTER TABLE hist_relation_member ADD PRIMARY KEY (relation_id, member_id, version);
    END IF;
END $$;
*/
