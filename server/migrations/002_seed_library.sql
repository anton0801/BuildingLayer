-- Seeds the server-managed reference library with the values the app shipped
-- hard-coded in 1.0. From here they can be corrected without an App Store
-- release; the app keeps its built-in copy as a fallback, so an empty or
-- unreachable server simply means the 1.0 catalogue.

SET NAMES utf8mb4;

INSERT INTO library_materials (slug, name, lambda, density, vapor_resistance, is_insulation, sort_order, is_active, updated_at) VALUES
  ('brick-outer',        'Brickwork (outer)',    0.77,  1700, 10,     0,  10, 1, UTC_TIMESTAMP()),
  ('concrete-block',     'Concrete block',       1.13,  2000, 60,     0,  20, 1, UTC_TIMESTAMP()),
  ('aac-block',          'Aerated block (AAC)',  0.15,   600, 10,     0,  30, 1, UTC_TIMESTAMP()),
  ('cement-render',      'Cement render',        0.87,  1800, 25,     0,  40, 1, UTC_TIMESTAMP()),
  ('plasterboard',       'Gypsum plasterboard',  0.21,   700,  8,     0,  50, 1, UTC_TIMESTAMP()),
  ('softwood',           'Softwood timber',      0.13,   500, 50,     0,  60, 1, UTC_TIMESTAMP()),
  ('osb',                'OSB / sheathing',      0.13,   650, 50,     0,  70, 1, UTC_TIMESTAMP()),
  ('plywood',            'Plywood',              0.14,   560, 110,    0,  80, 1, UTC_TIMESTAMP()),
  ('air-cavity',         'Air cavity (25mm)',    0.16,     1,  1,     0,  90, 1, UTC_TIMESTAMP()),
  ('screed',             'Screed',               1.15,  2000, 30,     0, 100, 1, UTC_TIMESTAMP()),
  ('reinforced-concrete','Reinforced concrete',  2.30,  2400, 130,    0, 110, 1, UTC_TIMESTAMP()),
  ('mineral-wool',       'Mineral wool (slab)',  0.035,   30,  1,     1, 200, 1, UTC_TIMESTAMP()),
  ('glass-wool',         'Glass wool (quilt)',   0.040,   16,  1,     1, 210, 1, UTC_TIMESTAMP()),
  ('eps',                'EPS board',            0.038,   18, 30,     1, 220, 1, UTC_TIMESTAMP()),
  ('xps',                'XPS board',            0.034,   35, 100,    1, 230, 1, UTC_TIMESTAMP()),
  ('pir',                'PIR board',            0.022,   30, 60,     1, 240, 1, UTC_TIMESTAMP()),
  ('phenolic',           'Phenolic board',       0.020,   35, 50,     1, 250, 1, UTC_TIMESTAMP()),
  ('wood-fibre',         'Wood fibre board',     0.040,  140,  5,     1, 260, 1, UTC_TIMESTAMP()),
  ('sheep-wool',         'Sheep wool',           0.039,   25,  1,     1, 270, 1, UTC_TIMESTAMP())
ON DUPLICATE KEY UPDATE
  name = VALUES(name), lambda = VALUES(lambda), density = VALUES(density),
  vapor_resistance = VALUES(vapor_resistance), is_insulation = VALUES(is_insulation),
  sort_order = VALUES(sort_order), is_active = VALUES(is_active), updated_at = UTC_TIMESTAMP();

INSERT INTO library_templates (slug, name, detail, element_type, layers_json, sort_order, is_active, updated_at) VALUES
  ('cavity-wall', 'Insulated cavity wall', 'Brick outer leaf, full-fill mineral wool, block inner leaf', 'Wall',
   '[{"material_name":"Brickwork (outer)","lambda":0.77,"vapor_resistance":10,"thickness_mm":102,"is_insulation":false,"side":"Outside"},{"material_name":"Mineral wool (slab)","lambda":0.035,"vapor_resistance":1,"thickness_mm":100,"is_insulation":true,"side":"Core"},{"material_name":"Concrete block","lambda":1.13,"vapor_resistance":60,"thickness_mm":100,"is_insulation":false,"side":"Inside"},{"material_name":"Gypsum plasterboard","lambda":0.21,"vapor_resistance":8,"thickness_mm":12.5,"is_insulation":false,"side":"Inside"}]',
   10, 1, UTC_TIMESTAMP()),
  ('ewi', 'External wall insulation', 'Render, PIR board over existing solid masonry', 'Wall',
   '[{"material_name":"Cement render","lambda":0.87,"vapor_resistance":25,"thickness_mm":15,"is_insulation":false,"side":"Outside"},{"material_name":"PIR board","lambda":0.022,"vapor_resistance":60,"thickness_mm":100,"is_insulation":true,"side":"Outside"},{"material_name":"Brickwork (outer)","lambda":0.77,"vapor_resistance":10,"thickness_mm":215,"is_insulation":false,"side":"Core"},{"material_name":"Gypsum plasterboard","lambda":0.21,"vapor_resistance":8,"thickness_mm":12.5,"is_insulation":false,"side":"Inside"}]',
   20, 1, UTC_TIMESTAMP()),
  ('timber-frame', 'Timber frame wall', 'Cladding, sheathing, insulated studs, service void', 'Wall',
   '[{"material_name":"Cement render","lambda":0.87,"vapor_resistance":25,"thickness_mm":15,"is_insulation":false,"side":"Outside"},{"material_name":"OSB / sheathing","lambda":0.13,"vapor_resistance":50,"thickness_mm":9,"is_insulation":false,"side":"Outside"},{"material_name":"Glass wool (quilt)","lambda":0.040,"vapor_resistance":1,"thickness_mm":140,"is_insulation":true,"side":"Core"},{"material_name":"OSB / sheathing","lambda":0.13,"vapor_resistance":50,"thickness_mm":9,"is_insulation":false,"side":"Inside"},{"material_name":"Gypsum plasterboard","lambda":0.21,"vapor_resistance":8,"thickness_mm":12.5,"is_insulation":false,"side":"Inside"}]',
   30, 1, UTC_TIMESTAMP()),
  ('cold-pitched-roof', 'Cold pitched roof', 'Quilt between and over ceiling joists', 'Roof',
   '[{"material_name":"Glass wool (quilt)","lambda":0.040,"vapor_resistance":1,"thickness_mm":100,"is_insulation":true,"side":"Outside"},{"material_name":"Softwood timber","lambda":0.13,"vapor_resistance":50,"thickness_mm":100,"is_insulation":false,"side":"Core"},{"material_name":"Glass wool (quilt)","lambda":0.040,"vapor_resistance":1,"thickness_mm":200,"is_insulation":true,"side":"Core"},{"material_name":"Gypsum plasterboard","lambda":0.21,"vapor_resistance":8,"thickness_mm":12.5,"is_insulation":false,"side":"Inside"}]',
   40, 1, UTC_TIMESTAMP()),
  ('warm-flat-roof', 'Warm flat roof', 'Membrane over PIR on a concrete deck', 'Roof',
   '[{"material_name":"PIR board","lambda":0.022,"vapor_resistance":60,"thickness_mm":140,"is_insulation":true,"side":"Outside"},{"material_name":"Reinforced concrete","lambda":2.3,"vapor_resistance":130,"thickness_mm":150,"is_insulation":false,"side":"Core"},{"material_name":"Gypsum plasterboard","lambda":0.21,"vapor_resistance":8,"thickness_mm":12.5,"is_insulation":false,"side":"Inside"}]',
   50, 1, UTC_TIMESTAMP()),
  ('insulated-ground-floor', 'Insulated ground floor', 'Screed over EPS on a concrete slab', 'Floor',
   '[{"material_name":"Reinforced concrete","lambda":2.3,"vapor_resistance":130,"thickness_mm":150,"is_insulation":false,"side":"Outside"},{"material_name":"EPS board","lambda":0.038,"vapor_resistance":30,"thickness_mm":120,"is_insulation":true,"side":"Core"},{"material_name":"Screed","lambda":1.15,"vapor_resistance":30,"thickness_mm":65,"is_insulation":false,"side":"Inside"}]',
   60, 1, UTC_TIMESTAMP()),
  ('suspended-timber-floor', 'Suspended timber floor', 'Wood fibre between joists, boarded over', 'Floor',
   '[{"material_name":"Wood fibre board","lambda":0.040,"vapor_resistance":5,"thickness_mm":150,"is_insulation":true,"side":"Outside"},{"material_name":"Softwood timber","lambda":0.13,"vapor_resistance":50,"thickness_mm":150,"is_insulation":false,"side":"Core"},{"material_name":"Plywood","lambda":0.14,"vapor_resistance":110,"thickness_mm":22,"is_insulation":false,"side":"Inside"}]',
   70, 1, UTC_TIMESTAMP())
ON DUPLICATE KEY UPDATE
  name = VALUES(name), detail = VALUES(detail), element_type = VALUES(element_type),
  layers_json = VALUES(layers_json), sort_order = VALUES(sort_order),
  is_active = VALUES(is_active), updated_at = UTC_TIMESTAMP();

-- Bumping the version is what tells every app that the catalogue moved.
UPDATE library_meta SET version = version + 1, updated_at = UTC_TIMESTAMP() WHERE id = 1;
