/**
 * Geometries are built from a given list of nodes at a given timestamp.
 * This class builds a geos geometry from this information, depending
 * on the tags, a way could possibly be a polygon. This information is
 * added additionally when building a portugal.
 */

#ifndef IMPORTER_GEOMBUILDER_HPP
#define IMPORTER_GEOMBUILDER_HPP

#include "project.hpp"

#include "geoscontext.hpp"

#include <osmium/osm/node_ref_list.hpp>

#include <iomanip>
#include <optional>
#include <string>
#include <utility>
#include <vector>

class GeomBuilder {

    Nodestore *m_nodestore;
    GeosContext m_geos;
    bool m_keepLatLng = false;
    bool m_debug = false;
    bool m_showerrors = false;

public:

    GeomBuilder(Nodestore *nodestore): m_nodestore(nodestore) {}

    GeosContext::Geometry forWay(
        const osmium::NodeRefList& nodes,
        osmium::Timestamp timestamp,
        bool looksLikePolygon
    ) {
        std::vector<std::pair<double, double>> coordinates;
        coordinates.reserve(nodes.size());
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
            if (!m_keepLatLng) {
                if (!Project::toMercator(&lon, &lat))
                    continue;
            }
            coordinates.emplace_back(lon, lat);
        }
        
        // if less then 2 nodes could be found in the store, no valid way
        // can be assembled and we need to skip it
        if (coordinates.size() < 2) {
            if (m_showerrors) {
                std::cerr << "found only " << coordinates.size()
                          << " valid coordinates, skipping way\n";
            }
            return {};
        }

        try {
            if (
                looksLikePolygon &&
                coordinates.front() == coordinates.back() &&
                coordinates.size() >= 4
            ) {
                return m_geos.createPolygon(coordinates, 3857);
            }
            return m_geos.createLineString(coordinates, 3857);
        } catch (const std::exception& e) {
            if (m_showerrors) {
                std::cerr << "error creating way geometry: " << e.what() << "\n";
            }
            return {};
        }
    }

    bool isPolygon(const GeosContext::Geometry& geometry) {
        return m_geos.typeId(geometry) == GEOS_POLYGON;
    }

    double area(const GeosContext::Geometry& geometry) {
        return m_geos.area(geometry);
    }

    std::string writeHexEWKB(const GeosContext::Geometry& geometry) {
        return m_geos.writeHexEWKB(geometry);
    }

    std::optional<std::pair<double, double>> pointOnSurface(
        const GeosContext::Geometry& geometry
    ) {
        return m_geos.pointOnSurface(geometry);
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
