#ifndef IMPORTER_HANDLER_HPP
#define IMPORTER_HANDLER_HPP

#include <fstream>

#include <libpq-fe.h>

#include <osmium/diff_handler.hpp>
#include <osmium/osm.hpp>

#include <geos/algorithm/InteriorPointArea.h>
#include <geos/io/WKBWriter.h>

#include "dbconn.hpp"
#include "dbcopyconn.hpp"

#include "nodestore.hpp"
#include "nodestore/stl.hpp"
#include "nodestore/sparse.hpp"

#include "polygonidentifyer.hpp"
#include "zordercalculator.hpp"
#include "hstore.hpp"
#include "timestamp.hpp"
#include "geombuilder.hpp"
#include "minortimescalculator.hpp"
#include "sorttest.hpp"
#include "project.hpp"

#include <memory>

class ImportHandler : public osmium::diff_handler::DiffHandler {

    Nodestore *m_store;
    GeomBuilder m_geom;
    MinorTimesCalculator m_mtimes;
    SortTest m_sorttest;

    DbConn m_general;
    DbCopyConn m_point;
    DbCopyConn m_line;
    DbCopyConn m_polygon;

    geos::io::WKBWriter wkb;

    std::string m_dsn;
    std::string m_prefix;
    bool m_debug;
    bool m_storeerrors;
    bool m_interior;
    bool m_keepLatLng;

    std::map<osmium::user_id_type, std::string> m_username_map;

    void write_node(const osmium::DiffNode& node) {
        const auto& cur = node.curr();

        if (m_debug) {
            std::cout << "node n" << cur.id() << 'v' << cur.version() << " at tstamp " << cur.timestamp() << " (" << cur.timestamp().to_iso() << ")\n";
        }

        std::string valid_from{cur.timestamp().to_iso()};
        std::string valid_to{"\\N"};

        // if this is another version of the same entity, the end-timestamp of the current entity is the timestamp of the next one
        if (!node.last()) {
            valid_to = node.next().timestamp().to_iso();
        }

        // if the current version is deleted, it's end-timestamp is the same as its creation-timestamp
        else if (!cur.visible()) {
            valid_to = valid_from;
        }

        // some xml-writers write deleted nodes without corrdinates, some write 0/0 as coorinate
        // default to 0/0 for those input nodes which dosn't carry corrdinates with them
        double lon = 0, lat = 0;
        if (cur.location().valid()) {
            lon = cur.location().lon();
            lat = cur.location().lat();
        }

        // if this node is not-deleted (ie visible), write it to the nodestore
        // some osm-writers write invisible nodes with 0/0 coordinates which would screw up rendering, if not ignored in the nodestore
        // see https://github.com/MaZderMind/osm-history-renderer/issues/8
        if (cur.visible()) {
            m_store->record(cur.id(), cur.uid(), cur.timestamp().seconds_since_epoch(), lon, lat);
        }

        m_username_map.emplace(cur.uid(), cur.user());

        if (!m_keepLatLng) {
            if (!Project::toMercator(&lon, &lat)) {
                return;
            }
        }

        // SPEED: sum up 64k of data, before sending them to the database
        // SPEED: instead of stringstream, which does dynamic allocation, use a fixed buffer and snprintf
        std::stringstream line;
        line << std::setprecision(8) <<
            cur.id() << '\t' <<
            cur.version() << '\t' <<
            (cur.visible() ? 't' : 'f') << '\t' <<
            cur.uid() << '\t' <<
            DbCopyConn::escape_string(cur.user()) << '\t' <<
            valid_from << '\t' <<
            valid_to << '\t' <<
            HStore::format(cur.tags()) << '\t';

        if (cur.visible()) {
            line << "SRID=3857;POINT(" << lon << ' ' << lat << ')';
        } else {
            line << "\\N";
        }

        line << '\n';
        m_point.copy(line.str());
    }

    void write_way(const osmium::DiffWay& way) {
        const auto& next = way.next();
        const auto& cur = way.curr();

        if (m_debug) {
            std::cout << "way w" << cur.id() << 'v' << cur.version() << " at tstamp " << cur.timestamp().seconds_since_epoch() << " (" << cur.timestamp().to_iso() << ")\n";
        }

        time_t valid_from = cur.timestamp().seconds_since_epoch();
        time_t valid_to = 0;

        std::vector<MinorTimesCalculator::MinorTimesInfo> *minor_times = nullptr;
        if (cur.visible()) {
            if (!way.last()) {
                if (cur.timestamp() > next.timestamp()) {
                    if (m_storeerrors) {
                        std::cerr << "inverse timestamp-order in way " << cur.id() << " between v" << cur.version() << " and v" << next.version() << ", skipping minor ways\n";
                    }
                } else {
                    // collect minor ways between current and next
                    minor_times = m_mtimes.forWay(cur.nodes(), cur.timestamp().seconds_since_epoch(), next.timestamp().seconds_since_epoch());
                }
            } else {
                // collect minor ways between current and the end
                minor_times = m_mtimes.forWay(cur.nodes(), cur.timestamp().seconds_since_epoch());
            }
        }

        // if there are minor ways, it's the timestamp of the first minor way
        if (minor_times && !minor_times->empty()) {
            valid_to = minor_times->front().t;
        }

        // if this is another version of the same entity, the end-timestamp of the current entity is the timestamp of the next one
        else if (!way.last()) {
            valid_to = next.timestamp().seconds_since_epoch();
        }

        // if the current version is deleted, it's end-timestamp is the same as its creation-timestamp
        else if (!cur.visible()) {
            valid_to = valid_from;
        }

        // write the main way version
        write_way_to_db(
            way,
            cur.id(),
            cur.version(),
            0 /*minor*/,
            cur.visible(),
            cur.uid(),
            cur.user(),
            cur.timestamp().seconds_since_epoch(),
            valid_from,
            valid_to,
            cur.tags(),
            cur.nodes()
        );

        if (minor_times) {
            // write the minor way versions of current between current & next
            int minor = 1;
            const auto end = minor_times->end();
            for (auto it = minor_times->begin(); it != end; it++) {
                if (m_debug) {
                    std::cout << "minor way w" << cur.id() << 'v' << cur.version() << '.' << minor << " at tstamp " << (*it).t << " (" << Timestamp::format( (*it).t ) << ")\n";
                }

                valid_from = (*it).t;
                if (it == end-1) {
                    if (!way.last()) {
                        valid_to = next.timestamp().seconds_since_epoch();
                    } else {
                        valid_to = 0;
                    }
                } else {
                    valid_to = ( *(it+1) ).t;
                }

                time_t t = (*it).t;
                osmium::user_id_type uid = (*it).uid;
                const char* user = m_username_map[ uid ].c_str();

                write_way_to_db(
                    way,
                    cur.id(),
                    cur.version(),
                    minor,
                    true,
                    uid,
                    user,
                    t,
                    valid_from,
                    valid_to,
                    cur.tags(),
                    cur.nodes()
                );

                minor++;
            }
            delete minor_times;
        }
    }

    void write_way_to_db(
        const osmium::DiffWay& way,
        osmium::object_id_type id,
        osmium::object_version_type version,
        osmium::object_version_type minor,
        bool visible,
        osmium::user_id_type user_id,
        const char* user_name,
        time_t timestamp,
        time_t valid_from,
        time_t valid_to,
        const osmium::TagList &tags,
        const osmium::NodeRefList &nodes
    ) {
        if (m_debug) {
            std::cerr << "forging geometry of way " << id << 'v' << version << '.' << minor << " at tstamp " << timestamp << "\n";
        }

        geos::geom::Geometry* geom = nullptr;
        if (visible) {
            bool looksLikePolygon = PolygonIdentifyer::looksLikePolygon(tags);
            geom = m_geom.forWay(nodes, timestamp, looksLikePolygon);
            if (!geom) {
                if (m_debug) {
                    std::cerr << "no valid geometry for way " << id << 'v' << version << '.' << minor << " at tstamp " << timestamp << "\n";
                }
                return;
            }
        }

        // SPEED: sum up 64k of data, before sending them to the database
        // SPEED: instead of stringstream, which does dynamic allocation, use a fixed buffer and snprintf
        std::stringstream line;
        line << std::setprecision(8) <<
            id << '\t' <<
            version << '\t' <<
            minor << '\t' <<
            (visible ? 't' : 'f') << '\t' <<
            user_id << '\t' <<
            DbCopyConn::escape_string(user_name) << '\t' <<
            Timestamp::formatDb(valid_from) << '\t' <<
            Timestamp::formatDb(valid_to) << '\t' <<
            HStore::format(tags) << '\t' <<
            ZOrderCalculator::calculateZOrder(tags) << '\t';

        if (geom == nullptr) {
            // this entity is deleted, we have no nd-refs and no tags from it to devide whether it once was a line or an areas
            if (!way.last()) {
                // if we have a previous version of this way (which we should have or this way has already been deleted in its initial version)
                // we can use the previous version to decide between line and area

                const auto&prev = way.prev();

                const bool looksLikePolygon = PolygonIdentifyer::looksLikePolygon(prev.tags());
                geom = m_geom.forWay(prev.nodes(), prev.timestamp(), looksLikePolygon);

                if (!geom) {
                    if (m_debug) {
                        std::cerr << "no valid geometry for way of " << prev.id() << 'v' << prev.version() << " which was consulted to determine if the deleted way " <<
                            id << "v" << version << " once was an area or a line. skipping that double-deleted way.\n";
                    }
                    return;
                }

                if (geom->getGeometryTypeId() == geos::geom::GEOS_POLYGON) {
                    line << /*area*/ "0\t" << /* geom */ "\\N\t" << /* center */ "\\N\n";
                    m_polygon.copy(line.str());
                } else {
                    line << /* geom */ "\\N\n";
                    m_line.copy(line.str());
                }
            }
        } else if (geom->getGeometryTypeId() == geos::geom::GEOS_POLYGON) {
            const geos::geom::Polygon* poly = dynamic_cast<const geos::geom::Polygon*>(geom);

            // a polygon, polygon-meta to table
            line << poly->getArea() << '\t';

            // write geometry to polygon table
            wkb.writeHEX(*geom, line);
            line << '\t';

            // calculate interior point
            if (m_interior) {
                try {
                    // will leak with invalid geometries on old geos code:
                    //  http://trac.osgeo.org/geos/ticket/475
                    geos::geom::Coordinate center;
                    geos::algorithm::InteriorPointArea interior_calculator(poly);
                    interior_calculator.getInteriorPoint(center);

                    // write interior point
                    line << "SRID=3857;POINT(" << center.x << ' ' << center.y << ')';
                } catch(geos::util::GEOSException e) {
                    std::cerr << "error calculating interior point: " << e.what() << "\n";
                    line << "\\N";
                }
            } else {
                line << "\\N";
            }

            line << '\n';
            m_polygon.copy(line.str());
        } else {
            // a linestring, write geometry to line-table
            wkb.writeHEX(*geom, line);

            line << '\n';
            m_line.copy(line.str());
        }
        delete geom;
    }

public:
    ImportHandler(Nodestore *nodestore):
            m_store(nodestore),
            m_geom(m_store),
            m_mtimes(m_store),
            m_sorttest(),
            wkb(),
            m_prefix("hist_") {
    }

    void dsn(std::string& newDsn) {
        m_dsn = newDsn;
    }

    void prefix(std::string& newPrefix) {
        m_prefix = newPrefix;
    }

    void printStoreErrors(bool shouldPrintStoreErrors) {
        m_storeerrors = shouldPrintStoreErrors;
        m_store->printStoreErrors(shouldPrintStoreErrors);
    }

    void calculateInterior(bool shouldCalculateInterior) {
        m_interior = shouldCalculateInterior;
    }

    void keepLatLng(bool shouldKeepLatLng) {
        m_keepLatLng = shouldKeepLatLng;
        m_geom.keepLatLng(shouldKeepLatLng);
    }

    void printDebugMessages(bool shouldPrintDebugMessages) {
        m_debug = shouldPrintDebugMessages;
        m_store->printDebugMessages(shouldPrintDebugMessages);
        m_geom.printDebugMessages(shouldPrintDebugMessages);
    }

    void init() {
        if (m_debug) {
            std::cerr << "connecting to database using dsn: " << m_dsn << "\n";
        }

        m_general.open(m_dsn);
        if (m_debug) {
            std::cerr << "running scheme/00-before.sql\n";
        }

        std::ifstream sqlfile{"scheme/00-before.sql"};
        if (!sqlfile) {
            sqlfile.open("/usr/share/osm-history-importer/scheme/00-before.sql");
        }

        if (!sqlfile) {
            throw std::runtime_error{"can't find 00-before.sql"};
        }

        m_general.execfile(sqlfile);

        m_point.open(m_dsn, m_prefix, "point");
        m_line.open(m_dsn, m_prefix, "line");
        m_polygon.open(m_dsn, m_prefix, "polygon");

        wkb.setIncludeSRID(true);
    }

    void final() {
        std::cerr << "closing point-table...\n";
        m_point.close();

        std::cerr << "closing line-table...\n";
        m_line.close();

        std::cerr << "closing polygon-table...\n";
        m_polygon.close();

        if (m_debug) {
            std::cerr << "running scheme/99-after.sql\n";
        }

        std::ifstream sqlfile{"scheme/99-after.sql"};
        if (!sqlfile) {
            sqlfile.open("/usr/share/osm-history-importer/scheme/99-after.sql");
        }

        if (!sqlfile) {
            throw std::runtime_error{"can't find 99-after.sql"};
        }

        m_general.execfile(sqlfile);

        if (m_debug) {
            std::cerr << "disconnecting from database\n";
        }
        m_general.close();
    }

    void node(const osmium::DiffNode& node) {
        m_sorttest.test(node.curr());
        write_node(node);
    }

    void way(const osmium::DiffWay& way) {
        m_sorttest.test(way.curr());
        write_way(way);
    }

};

#endif // IMPORTER_HANDLER_HPP
