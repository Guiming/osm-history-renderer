#include "../geoscontext.hpp"

#include <cassert>
#include <cmath>
#include <string>
#include <utility>
#include <vector>

int main() {
    GeosContext geos;
    const std::vector<std::pair<double, double>> coordinates{
        {0.0, 0.0},
        {10.0, 0.0},
        {10.0, 10.0},
        {0.0, 10.0},
        {0.0, 0.0},
    };

    auto polygon = geos.createPolygon(coordinates, 3857);
    assert(polygon);
    assert(geos.typeId(polygon) == GEOS_POLYGON);
    assert(std::abs(geos.area(polygon) - 100.0) < 1e-12);

    const std::string ewkb = geos.writeHexEWKB(polygon);
    assert(ewkb.rfind("0103000020110F0000", 0) == 0);

    const auto point = geos.pointOnSurface(polygon);
    assert(point.has_value());
    assert(point->first >= 0.0 && point->first <= 10.0);
    assert(point->second >= 0.0 && point->second <= 10.0);
}
