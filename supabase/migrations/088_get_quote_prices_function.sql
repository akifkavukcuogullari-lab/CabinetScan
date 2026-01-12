-- =============================================
-- GET_QUOTE_PRICES FUNCTION
-- Adapted to use price_catalog table with size as TEXT
-- =============================================

CREATE OR REPLACE FUNCTION get_quote_prices(
  p_showroom_id UUID,
  p_cabinets JSONB,
  p_style TEXT DEFAULT 'Shaker',
  p_color TEXT DEFAULT 'White'
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  cabinet JSONB;
  result JSONB := '[]'::JSONB;
  found_price DECIMAL;
  found_size TEXT;
  match_level TEXT;
  cabinet_total DECIMAL := 0;
  accessory_total DECIMAL := 0;
  cab_type TEXT;
  cab_size TEXT;
BEGIN
  -- Loop through each cabinet
  FOR cabinet IN SELECT * FROM jsonb_array_elements(p_cabinets)
  LOOP
    cab_type := cabinet->>'type';
    -- Size can be passed as "size" field or constructed from width x height x depth
    cab_size := COALESCE(
      cabinet->>'size',
      CASE
        WHEN cabinet->>'width' IS NOT NULL AND cabinet->>'height' IS NOT NULL AND cabinet->>'depth' IS NOT NULL
        THEN (cabinet->>'width') || 'x' || (cabinet->>'height') || 'x' || (cabinet->>'depth')
        WHEN cabinet->>'width' IS NOT NULL AND cabinet->>'height' IS NOT NULL
        THEN (cabinet->>'width') || 'x' || (cabinet->>'height')
        WHEN cabinet->>'width' IS NOT NULL
        THEN cabinet->>'width'
        ELSE NULL
      END
    );

    found_price := NULL;
    found_size := NULL;
    match_level := 'not_found';

    -- LEVEL 1: Try exact match (type + size + style + color)
    SELECT price, size INTO found_price, found_size
    FROM price_catalog
    WHERE showroom_id = p_showroom_id
      AND LOWER(type) = LOWER(cab_type)
      AND LOWER(size) = LOWER(cab_size)
      AND LOWER(style) = LOWER(p_style)
      AND LOWER(color) = LOWER(p_color)
    LIMIT 1;

    IF found_price IS NOT NULL THEN
      match_level := 'exact';
    ELSE
      -- LEVEL 2: Same type + style + color, any size
      SELECT price, size INTO found_price, found_size
      FROM price_catalog
      WHERE showroom_id = p_showroom_id
        AND LOWER(type) = LOWER(cab_type)
        AND LOWER(style) = LOWER(p_style)
        AND LOWER(color) = LOWER(p_color)
      LIMIT 1;

      IF found_price IS NOT NULL THEN
        match_level := 'style_color_match';
      ELSE
        -- LEVEL 3: Same type + size only (ignore style/color)
        SELECT price, size INTO found_price, found_size
        FROM price_catalog
        WHERE showroom_id = p_showroom_id
          AND LOWER(type) = LOWER(cab_type)
          AND LOWER(size) = LOWER(cab_size)
        LIMIT 1;

        IF found_price IS NOT NULL THEN
          match_level := 'type_size_match';
        ELSE
          -- LEVEL 4: Same type only
          SELECT price, size INTO found_price, found_size
          FROM price_catalog
          WHERE showroom_id = p_showroom_id
            AND LOWER(type) = LOWER(cab_type)
          LIMIT 1;

          IF found_price IS NOT NULL THEN
            match_level := 'type_only';
          END IF;
        END IF;
      END IF;
    END IF;

    -- Add to totals
    IF cab_type ILIKE '%filler%' OR cab_type ILIKE '%molding%' OR cab_type ILIKE '%handle%' THEN
      accessory_total := accessory_total + COALESCE(found_price, 0);
    ELSE
      cabinet_total := cabinet_total + COALESCE(found_price, 0);
    END IF;

    -- Add to result array
    result := result || jsonb_build_object(
      'id', cabinet->>'id',
      'type', cab_type,
      'requested_size', cab_size,
      'matched_size', found_size,
      'price', COALESCE(found_price, 0),
      'match_level', match_level
    );
  END LOOP;

  -- Return complete quote
  RETURN jsonb_build_object(
    'line_items', result,
    'cabinet_subtotal', cabinet_total,
    'accessory_subtotal', accessory_total,
    'grand_total', cabinet_total + accessory_total,
    'item_count', jsonb_array_length(p_cabinets),
    'style', p_style,
    'color', p_color
  );
END;
$$;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_quote_prices TO authenticated;
GRANT EXECUTE ON FUNCTION get_quote_prices TO anon;

COMMENT ON FUNCTION get_quote_prices IS
'Looks up prices from price_catalog for a list of cabinets.
Supports fallback matching: exact > style+color > type+size > type only.
Size can be passed as "size" field or will be constructed from "width" x "height" x "depth".';

-- =============================================
-- TEST THE FUNCTION
-- =============================================

/*
SELECT get_quote_prices(
  'your-showroom-uuid-here'::UUID,
  '[
    {"id": "B1", "type": "Base Cabinet", "size": "36x34.5x24"},
    {"id": "B2", "type": "Base Cabinet", "width": "21", "height": "34.5", "depth": "24"},
    {"id": "U1", "type": "Wall Cabinet", "size": "36x42x12"}
  ]'::JSONB,
  'Shaker',
  'White'
);
*/
