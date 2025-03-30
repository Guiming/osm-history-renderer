/**
 * Geometries are built from a given list of nodes at a given timestamp.
 * This class builds a geos geometry from this information, depending
 * on the tags, a way could possibly be a polygon. This information is
 * added additionally when building a portugal.
 */

#ifndef IMPORTER_GEOMBUILDER_HPP
#define IMPORTER_GEOMBUILDER_HPP

#include "project.hpp"

#include <osmium/osm/node_ref_list.hpp>
#include <osmium/geom/geos.hpp>

#include <geos/geom/GeometryFactory.h>
#include <geos/geom/PrecisionModel.h>
#include <geos/geom/Coordinate.h>
#include <geos/geom/CoordinateSequence.h>
#include <geos/geom/CoordinateSequenceFactory.h>
#include <geos/geom/Point.h>
#include <geos/geom/LinearRing.h>
#include <geos/geom/Polygon.h>
#include <geos/geom/MultiPolygon.h>

#include <iomanip>

inline geos::geom::GeometryFactory* geos_geometry_factory() {
    static geos::geom::PrecisionModel pm;
    static auto factory = geos::geom::GeometryFactory::create(&pm, -1);
    return factory.get();
}

class GeomBuilder {

    Nodestore *m_nodestore;
    bool m_keepLatLng = false;
    bool m_debug = false;
    bool m_showerrors = false;

public:

    GeomBuilder(Nodestore *nodestore): m_nodestore(nodestore) {}

    geos::geom::Geometry* forWay(const osmium::NodeRefList &nodes, osmium::Timestamp timestamp, bool looksLikePolygon) {
        // shorthand to the geometry factory
        geos::geom::GeometryFactory *f = geos_geometry_factory();
        
        // pointer to coordinate vector
        std::vector<geos::geom::Coordinate> *c = new std::vector<geos::geom::Coordinate>();
        for (const auto& nr : nodes) {
            // was the node found in the store?
            bool found;
            Nodestore::Nodeinfo info = m_nodestore->lookup(nr.ref(), timestamp.seconds_since_epoch(), found);

            // a missing node can just be skipped
            if (!found) {
                continue;
            }
            double lon = info.lon, lat = info.lat;
            if (m_debug) {
                std::cerr << "node #" << nr.ref() << " at tstamp " << timestamp.seconds_since_epoch() << " references node at POINT(" << std::setprecision(8) << lon << ' ' << lat << ")\n";
            }
            // create a coordinate-object and add it to the vector
            if (!m_keepLatLng) {
                if (!Project::toMercator(&lon, &lat))
                    continue;
            }
            c->push_back(geos::geom::Coordinate{lon, lat, geos::DoubleNotANumber});
        }
        
        // if less then 2 nodes could be found in the store, no valid way
        // can be assembled and we need to skip it
        if (c->size() < 2) {
            if (m_showerrors) {
                std::cerr << "found only " << c->size() << " valid coordinates, skipping way\n";
            }
            delete c;
            return nullptr;
        }

        // the resulting geometry
        geos::geom::Geometry* geom;

        // geos throws exception on bad geometries and such
        try {
            // tags say it could be a polygon, the way is closed and has
            // at least 3 *different* coordinates
            if (looksLikePolygon && c->front() == c->back() && c->size() >= 4) {
                // build a polygon
                geom = f->createPolygon(
                    f->createLinearRing(
                        f->getCoordinateSequenceFactory()->create(c)
                    ).release(), //.get(),
                    nullptr
                );
            } else {
                // build a linestring
                
                geom = f->createLineString(
                    f->getCoordinateSequenceFactory()->create(c)
                ).release(); //.get();

            }
        } catch (const geos::util::GEOSException& e) {
            if (m_showerrors) {
                std::cerr << "error creating polygon: " << e.what() << "\n";
            }
            delete c;
            return nullptr;
        }
        // enforce srid
        if (geom) {
            geom->setSRID(3857);
        }

        return geom;
    }

    void keepLatLng(bool shouldKeepLatLng) {
        m_keepLatLng = shouldKeepLatLng;
    }

    /**
     * should this nodestore print debug messages
     */
    void printDebugMessages(bool shouldPrintDebugMessages) {
        m_debug = shouldPrintDebugMessages;
    }
};

#endif // IMPORTER_GEOMBUILDER_HPP
