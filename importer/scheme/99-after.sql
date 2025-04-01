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
-- maybe it's better to run the following after all imports are done?
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
-- maybe it's better to run the following after all imports are done?
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
-- maybe it's better to run the following after all imports are done?
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
-- maybe it's better to run the following after all imports are done?
--/*
CREATE INDEX IF NOT EXISTS hist_relation_time_index ON hist_relation USING BTREE (valid_from, valid_to);
CREATE INDEX IF NOT EXISTS hist_relation_validfrom ON hist_relation USING BTREE (valid_from);
CREATE INDEX IF NOT EXISTS hist_relation_validto ON hist_relation USING BTREE (valid_to);
CREATE INDEX IF NOT EXISTS hist_relation_uid ON hist_relation (user_id);
CREATE INDEX IF NOT EXISTS hist_relation_changeset ON hist_relation USING BTREE (changeset);

-- have to skip this as there might be duplicated (relation_id, member_id, version), not sure why.
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


/* build polygons from hist_relation and hist_relation_member */
-- maybe it's better to run the following after all imports are done?

/*
-------------------------------------------
DROP TABLE IF EXISTS _outer_inner_rings;
CREATE TABLE _outer_inner_rings AS
	(WITH poly AS
		(SELECT DISTINCT R.id AS r_id, R.version AS r_version, R.valid_from AS r_timestamp, RM.role, P.id, P.version, P.minor, 
		P.visible, P.user_id, /*P.user_name,*/ P.changeset, P.valid_from, P.valid_to, P.tags, P.z_order, 
			ST_ExteriorRing(P.geom) AS geom
		FROM hist_relation AS R, hist_relation_member AS RM, hist_polygon AS P
		WHERE (R.id, R.version) = (RM.relation_id, RM.version) AND RM.member_id = P.id
			   AND RM.member_type = 'way' AND LOWER(RM.role) IN ('outer', 'inner')
			   AND R.valid_from >= P.valid_from AND R.valid_from < COALESCE(P.valid_to, '9999-12-31')
		),
	line AS
		(SELECT DISTINCT R.id AS r_id, R.version AS r_version, R.valid_from AS r_timestamp, RM.role, P.*
		FROM hist_relation AS R, hist_relation_member AS RM, hist_line AS P
		WHERE (R.id, R.version) = (RM.relation_id, RM.version) 
				AND RM.member_id = P.id
			   AND RM.member_type = 'way' 
			   AND LOWER(RM.role) IN ('outer', 'inner')
			   AND R.valid_from >= P.valid_from AND R.valid_from < COALESCE(P.valid_to, '9999-12-31')
		)
		SELECT poly.* FROM poly
		UNION
		SELECT line.* FROM line
);

-----------------------------------------------------------
DROP TABLE IF EXISTS hist_polygon_from_relation;
CREATE TABLE hist_polygon_from_relation AS 
(
	WITH counts AS (
		SELECT R.id, R.version, 
			COUNT(CASE WHEN role = 'outer' THEN 1 END) AS n_outer, 
			COUNT(CASE WHEN role = 'inner' THEN 1 END) AS n_inner
		FROM hist_relation AS R, hist_relation_member AS RM
		WHERE (R.id, R.version) = (RM.relation_id, RM.version)
		AND RM.member_type = 'way' AND LOWER(RM.role) IN ('outer', 'inner')
		GROUP BY R.id, R.version
	),
	aggregated_geoms AS (
	    -- Step 1: Aggregate geometries by id and version
	    SELECT 
	        r_id, 
	        r_version, 
			COUNT(CASE WHEN role = 'outer' THEN 1 END) AS _n_outer, 
			COUNT(CASE WHEN role = 'inner' THEN 1 END) AS _n_inner,
	        ST_Union(CASE WHEN role = 'outer' THEN geom END) AS outer_geom, 
	        ST_Union(CASE WHEN role = 'inner' THEN geom END) AS inner_geom
	    FROM _outer_inner_rings
	    GROUP BY r_id, r_version
	
	),
	polygons AS (
	    -- Step 2: Create polygons from outer and inner geometries
	    SELECT 
	        r_id, 
	        r_version, 
	        (SELECT ST_Collect(geom) FROM ST_Dump(ST_Polygonize(outer_geom))) AS outer_polygon,
	        (SELECT ST_Collect(geom) FROM ST_Dump(ST_Polygonize(inner_geom))) AS inner_polygon
	    FROM aggregated_geoms, counts AS C
	    --WHERE ST_IsClosed(outer_geom) -- Ensure the outer geometry is closed -- does not seem needed
		WHERE (r_id, r_version) = (C.id, C.version) AND (_n_outer, _n_inner) = (n_outer, n_inner)
		GROUP BY r_id, r_version
	)
	-- Step 3: Create a MultiPolygon with inner polygons as holes
	SELECT 
	    r_id AS id, 
	    r_version AS version,
		0 AS minor,
		R.visible,
		R.user_id,
		R.changeset,
		R.valid_from AS valid_from,
		R.valid_to AS valid_to,
		R.tags AS tags,
		0 AS z_order,
		NULL::real AS area,
	    CASE 
			WHEN outer_polygon IS NULL 
		        THEN NULL
		    WHEN inner_polygon IS NULL 
		        THEN outer_polygon
		    ELSE 
				ST_Multi(ST_Difference(outer_polygon, inner_polygon))
	    END AS geom,
		NULL::geometry AS center
	FROM polygons, hist_relation AS R
	WHERE (r_id, r_version) = (R.id, R.version)
);

ALTER TABLE hist_polygon 
    ADD COLUMN IF NOT EXISTS mpolygon_index INTEGER;

UPDATE hist_polygon	
	SET mpolygon_index = 0;

ALTER TABLE hist_polygon
	DROP CONSTRAINT IF EXISTS hist_polygon_pkey,
    ADD CONSTRAINT hist_polygon_pkey PRIMARY KEY (id, version, minor, mpolygon_index);

INSERT INTO hist_polygon
SELECT 
		P.id, 
	    P.version,
		P.minor,
		P.visible,
		P.user_id,
		P.changeset,
		P.valid_from,
		P.valid_to,
		P.tags,
		P.z_order,
		P.area,
    	dumped.geom::geometry(POLYGON),
		p.center,
		dumped.path[1] AS mpolygon_index
FROM hist_polygon_from_relation AS P,
	LATERAL ST_Dump(p.geom) AS dumped
WHERE ST_GeometryType(dumped.geom) = 'ST_Polygon';

UPDATE hist_polygon
SET area = ST_Area(geom)
WHERE area IS NULL;

DROP TABLE _outer_inner_rings;

--DROP TABLE hist_polygon_from_relation;
DELETE 
FROM hist_polygon_from_relation 
WHERE geom IS NULL;
*/