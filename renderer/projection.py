import mapnik

# Define Mercator projection
# Define the Web Mercator (EPSG:3857) and WGS84 (EPSG:4326) projections
web_mercator = mapnik.Projection('+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +wktext +no_defs')
wgs84 = mapnik.Projection('+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs')
transform = mapnik.ProjTransform(wgs84, web_mercator)

bbox = [-20037508.342789244,-19971868.880408566,20037508.342789244,19971868.880408566]
c0 = transform.backward(mapnik.Coord(bbox[0],bbox[1]))
c1 = transform.backward(mapnik.Coord(bbox[2],bbox[3]))
e = mapnik.Box2d(c0.x,c0.y,c1.x,c1.y)
print("Geographic BBOX:", e)

bbox = [-180, -85, 180, 85]
c0 = transform.forward(mapnik.Coord(bbox[0],bbox[1]))
c1 = transform.forward(mapnik.Coord(bbox[2],bbox[3]))
e = mapnik.Box2d(c0.x,c0.y,c1.x,c1.y)
print("Projected BBOX:", e)

e = mapnik.forward_(mapnik.Box2d(*bbox), web_mercator)
print("Projected BBOX:", e)

