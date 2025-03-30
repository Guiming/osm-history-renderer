ALTER TABLE hist_point ADD PRIMARY KEY (id, version);
--CREATE INDEX hist_line_geom_and_time_index ON hist_line USING GIST (geom, valid_from, valid_to); // can't use GIST on timestamp
CREATE INDEX hist_point_geom ON hist_point USING GIST (geom);
CREATE INDEX hist_point_time_index ON hist_point USING BTREE (valid_from, valid_to);
CREATE INDEX hist_point_validfrom ON hist_point USING BTREE (valid_from);
CREATE INDEX hist_point_validto ON hist_point USING BTREE (valid_to);
CREATE INDEX hist_point_uid ON hist_point (user_id);

ALTER TABLE hist_line ADD PRIMARY KEY (id, version, minor);
--CREATE INDEX hist_line_geom_and_time_index ON hist_line USING GIST (geom, valid_from, valid_to);
CREATE INDEX hist_line_geom ON hist_line USING GIST (geom);
CREATE INDEX hist_line_time_index ON hist_line USING BTREE (valid_from, valid_to);
CREATE INDEX hist_line_validfrom ON hist_line USING BTREE (valid_from);
CREATE INDEX hist_line_validto ON hist_line USING BTREE (valid_to);
CREATE INDEX hist_line_uid ON hist_line (user_id);

ALTER TABLE hist_polygon ADD PRIMARY KEY (id, version, minor);
--CREATE INDEX hist_polygon_geom_and_time_index ON hist_polygon USING GIST (geom, valid_from, valid_to);
CREATE INDEX hist_polygon_geom ON hist_polygon USING GIST (geom);
CREATE INDEX hist_polygon_time_index ON hist_polygon USING BTREE (valid_from, valid_to);
CREATE INDEX hist_polygon_validfrom ON hist_polygon USING BTREE (valid_from);
CREATE INDEX hist_polygon_validto ON hist_polygon USING BTREE (valid_to);
CREATE INDEX hist_polygon_uid ON hist_polygon (user_id);
