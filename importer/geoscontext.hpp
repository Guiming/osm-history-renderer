#ifndef IMPORTER_GEOSCONTEXT_HPP
#define IMPORTER_GEOSCONTEXT_HPP

#define GEOS_USE_ONLY_R_API
#include <geos_c.h>

#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

class GeosContext {
public:
    struct GeometryDeleter {
        GEOSContextHandle_t context = nullptr;

        void operator()(GEOSGeometry* geometry) const noexcept {
            if (geometry != nullptr && context != nullptr) {
                GEOSGeom_destroy_r(context, geometry);
            }
        }
    };

    using Geometry = std::unique_ptr<GEOSGeometry, GeometryDeleter>;

private:
    struct CoordinateSequenceDeleter {
        GEOSContextHandle_t context = nullptr;

        void operator()(GEOSCoordSequence* sequence) const noexcept {
            if (sequence != nullptr && context != nullptr) {
                GEOSCoordSeq_destroy_r(context, sequence);
            }
        }
    };

    using CoordinateSequence =
        std::unique_ptr<GEOSCoordSequence, CoordinateSequenceDeleter>;

    GEOSContextHandle_t m_context = nullptr;
    GEOSWKBWriter* m_writer = nullptr;
    std::string m_last_error;

    static void captureError(const char* message, void* user_data) noexcept {
        if (user_data == nullptr) {
            return;
        }
        try {
            auto* self = static_cast<GeosContext*>(user_data);
            self->m_last_error = message == nullptr ? "unknown GEOS error" : message;
        } catch (...) {
        }
    }

    [[noreturn]] void throwError(const std::string& operation) const {
        if (m_last_error.empty()) {
            throw std::runtime_error(operation + " failed");
        }
        throw std::runtime_error(operation + " failed: " + m_last_error);
    }

    CoordinateSequence createCoordinateSequence(
        const std::vector<std::pair<double, double>>& coordinates
    ) {
        std::vector<double> x;
        std::vector<double> y;
        x.reserve(coordinates.size());
        y.reserve(coordinates.size());
        for (const auto& coordinate : coordinates) {
            x.push_back(coordinate.first);
            y.push_back(coordinate.second);
        }

        m_last_error.clear();
        auto* sequence = GEOSCoordSeq_copyFromArrays_r(
            m_context,
            x.data(),
            y.data(),
            nullptr,
            nullptr,
            static_cast<unsigned int>(coordinates.size())
        );
        if (sequence == nullptr) {
            throwError("creating a coordinate sequence");
        }
        return CoordinateSequence{sequence, CoordinateSequenceDeleter{m_context}};
    }

    Geometry own(GEOSGeometry* geometry, const std::string& operation) {
        if (geometry == nullptr) {
            throwError(operation);
        }
        return Geometry{geometry, GeometryDeleter{m_context}};
    }

public:
    GeosContext() {
        m_context = GEOS_init_r();
        if (m_context == nullptr) {
            throw std::runtime_error("initializing GEOS failed");
        }
        GEOSContext_setErrorMessageHandler_r(m_context, captureError, this);

        m_writer = GEOSWKBWriter_create_r(m_context);
        if (m_writer == nullptr) {
            GEOS_finish_r(m_context);
            m_context = nullptr;
            throw std::runtime_error("creating the GEOS WKB writer failed");
        }
        GEOSWKBWriter_setByteOrder_r(m_context, m_writer, GEOS_WKB_NDR);
        GEOSWKBWriter_setFlavor_r(m_context, m_writer, GEOS_WKB_EXTENDED);
        GEOSWKBWriter_setIncludeSRID_r(m_context, m_writer, 1);
        GEOSWKBWriter_setOutputDimension_r(m_context, m_writer, 2);
    }

    ~GeosContext() {
        if (m_writer != nullptr) {
            GEOSWKBWriter_destroy_r(m_context, m_writer);
        }
        if (m_context != nullptr) {
            GEOS_finish_r(m_context);
        }
    }

    GeosContext(const GeosContext&) = delete;
    GeosContext& operator=(const GeosContext&) = delete;
    GeosContext(GeosContext&&) = delete;
    GeosContext& operator=(GeosContext&&) = delete;

    Geometry createLineString(
        const std::vector<std::pair<double, double>>& coordinates,
        int srid
    ) {
        if (coordinates.size() < 2) {
            throw std::invalid_argument("a line string needs at least two coordinates");
        }
        auto sequence = createCoordinateSequence(coordinates);
        m_last_error.clear();
        auto geometry = own(
            GEOSGeom_createLineString_r(m_context, sequence.release()),
            "creating a line string"
        );
        GEOSSetSRID_r(m_context, geometry.get(), srid);
        return geometry;
    }

    Geometry createPolygon(
        const std::vector<std::pair<double, double>>& coordinates,
        int srid
    ) {
        if (coordinates.size() < 4 || coordinates.front() != coordinates.back()) {
            throw std::invalid_argument(
                "a polygon shell needs at least four coordinates and must be closed"
            );
        }

        auto sequence = createCoordinateSequence(coordinates);
        m_last_error.clear();
        auto shell = own(
            GEOSGeom_createLinearRing_r(m_context, sequence.release()),
            "creating a polygon shell"
        );
        m_last_error.clear();
        auto geometry = own(
            GEOSGeom_createPolygon_r(m_context, shell.release(), nullptr, 0),
            "creating a polygon"
        );
        GEOSSetSRID_r(m_context, geometry.get(), srid);
        return geometry;
    }

    int typeId(const Geometry& geometry) {
        m_last_error.clear();
        const int type = GEOSGeomTypeId_r(m_context, geometry.get());
        if (type < 0) {
            throwError("reading a geometry type");
        }
        return type;
    }

    double area(const Geometry& geometry) {
        double result = 0.0;
        m_last_error.clear();
        if (GEOSArea_r(m_context, geometry.get(), &result) == 0) {
            throwError("calculating polygon area");
        }
        return result;
    }

    std::string writeHexEWKB(const Geometry& geometry) {
        std::size_t size = 0;
        m_last_error.clear();
        unsigned char* buffer =
            GEOSWKBWriter_writeHEX_r(m_context, m_writer, geometry.get(), &size);
        if (buffer == nullptr) {
            throwError("serializing geometry as EWKB");
        }
        std::string result{reinterpret_cast<char*>(buffer), size};
        GEOSFree_r(m_context, buffer);
        return result;
    }

    std::optional<std::pair<double, double>> pointOnSurface(
        const Geometry& geometry
    ) {
        m_last_error.clear();
        auto point = own(
            GEOSPointOnSurface_r(m_context, geometry.get()),
            "calculating a point on surface"
        );
        double x = 0.0;
        double y = 0.0;
        if (
            GEOSGeomGetX_r(m_context, point.get(), &x) == 0 ||
            GEOSGeomGetY_r(m_context, point.get(), &y) == 0
        ) {
            return std::nullopt;
        }
        return std::make_pair(x, y);
    }
};

#endif
