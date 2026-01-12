import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

interface UploadPriceCatalogRequest {
  showroom_id: string
  csv_content: string
}

interface CatalogRow {
  type: string
  size: string | null
  style: string | null
  color: string | null
  price: number | null
  description: string | null
  sku: string | null
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Method not allowed' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  try {
    const { showroom_id, csv_content }: UploadPriceCatalogRequest = await req.json()

    if (!showroom_id) {
      return new Response(
        JSON.stringify({ error: 'showroom_id is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!csv_content || csv_content.trim() === '') {
      return new Response(
        JSON.stringify({ error: 'csv_content is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify showroom exists
    const { data: showroom, error: showroomError } = await supabaseAdmin
      .from('showrooms')
      .select('id, name')
      .eq('id', showroom_id)
      .single()

    if (showroomError || !showroom) {
      return new Response(
        JSON.stringify({ error: 'Showroom not found' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log(`[CATALOG] Processing price catalog for showroom: ${showroom.name}`)

    // Parse CSV content
    const rows = parseCSV(csv_content)
    console.log(`[CATALOG] Parsed ${rows.length} rows from CSV`)

    if (rows.length === 0) {
      return new Response(
        JSON.stringify({ error: 'No valid rows found in CSV' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Delete existing entries for this showroom (replace mode)
    console.log(`[CATALOG] Deleting existing entries for showroom ${showroom_id}`)
    const { error: deleteError } = await supabaseAdmin
      .from('price_catalog')
      .delete()
      .eq('showroom_id', showroom_id)

    if (deleteError) {
      console.error('[CATALOG] Error deleting existing entries:', deleteError)
      throw new Error(`Failed to delete existing entries: ${deleteError.message}`)
    }

    // Insert new entries
    console.log(`[CATALOG] Inserting ${rows.length} new entries...`)
    const insertData = rows.map((row) => ({
      showroom_id,
      type: row.type,
      size: row.size,
      style: row.style,
      color: row.color,
      price: row.price,
      description: row.description,
      sku: row.sku,
    }))

    // Insert in batches of 100 to avoid hitting limits
    const INSERT_BATCH_SIZE = 100
    let insertedCount = 0

    for (let i = 0; i < insertData.length; i += INSERT_BATCH_SIZE) {
      const batch = insertData.slice(i, i + INSERT_BATCH_SIZE)
      const { error: insertError } = await supabaseAdmin
        .from('price_catalog')
        .insert(batch)

      if (insertError) {
        console.error('[CATALOG] Error inserting batch:', insertError)
        throw new Error(`Failed to insert entries: ${insertError.message}`)
      }

      insertedCount += batch.length
      console.log(`[CATALOG] Inserted ${insertedCount}/${insertData.length} entries`)
    }

    console.log(`[CATALOG] Successfully uploaded ${insertedCount} catalog entries`)

    return new Response(
      JSON.stringify({
        success: true,
        message: `Successfully uploaded ${insertedCount} catalog entries`,
        showroom_id,
        showroom_name: showroom.name,
        row_count: insertedCount,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('[CATALOG] Error uploading price catalog:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

/**
 * Normalize size string to use consistent format
 * - Replaces × (multiplication sign U+00D7) with x (letter)
 * - Replaces other multiplication-like characters
 * - Trims whitespace around separators
 */
function normalizeSize(size: string | null): string | null {
  if (!size) return null

  return size
    .replace(/×/g, 'x')      // U+00D7 multiplication sign
    .replace(/✕/g, 'x')      // U+2715 multiplication x
    .replace(/✖/g, 'x')      // U+2716 heavy multiplication x
    .replace(/╳/g, 'x')      // U+2573 box drawings light diagonal cross
    .replace(/\s*x\s*/gi, 'x') // Normalize spacing around x
    .trim()
}

/**
 * Parse CSV content into catalog rows
 * Expected columns: type, size, style, color, price (optional: description, sku)
 */
function parseCSV(csvContent: string): CatalogRow[] {
  const lines = csvContent.trim().split('\n')
  if (lines.length < 2) {
    return []
  }

  // Parse header row
  const header = parseCSVLine(lines[0])
  const columnIndices = {
    type: header.findIndex(h => h.toLowerCase() === 'type'),
    size: header.findIndex(h => h.toLowerCase() === 'size'),
    style: header.findIndex(h => h.toLowerCase() === 'style'),
    color: header.findIndex(h => h.toLowerCase() === 'color'),
    price: header.findIndex(h => h.toLowerCase() === 'price'),
    description: header.findIndex(h => h.toLowerCase() === 'description'),
    sku: header.findIndex(h => h.toLowerCase() === 'sku'),
  }

  // Type is required
  if (columnIndices.type === -1) {
    throw new Error('CSV must have a "type" column')
  }

  const rows: CatalogRow[] = []

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim()
    if (!line) continue

    const values = parseCSVLine(line)

    const type = columnIndices.type >= 0 ? values[columnIndices.type]?.trim() : null
    const rawSize = columnIndices.size >= 0 ? values[columnIndices.size]?.trim() || null : null
    const size = normalizeSize(rawSize) // Normalize × to x
    const style = columnIndices.style >= 0 ? values[columnIndices.style]?.trim() || null : null
    const color = columnIndices.color >= 0 ? values[columnIndices.color]?.trim() || null : null
    const priceStr = columnIndices.price >= 0 ? values[columnIndices.price]?.trim() : null
    const price = priceStr ? parseFloat(priceStr.replace(/[^0-9.]/g, '')) : null
    const description = columnIndices.description >= 0 ? values[columnIndices.description]?.trim() || null : null
    const sku = columnIndices.sku >= 0 ? values[columnIndices.sku]?.trim() || null : null

    if (!type) continue

    rows.push({
      type,
      size,
      style,
      color,
      price: price && !isNaN(price) ? price : null,
      description,
      sku,
    })
  }

  return rows
}

/**
 * Parse a single CSV line, handling quoted values
 */
function parseCSVLine(line: string): string[] {
  const values: string[] = []
  let current = ''
  let inQuotes = false

  for (let i = 0; i < line.length; i++) {
    const char = line[i]

    if (char === '"') {
      if (inQuotes && line[i + 1] === '"') {
        // Escaped quote
        current += '"'
        i++
      } else {
        inQuotes = !inQuotes
      }
    } else if (char === ',' && !inQuotes) {
      values.push(current)
      current = ''
    } else {
      current += char
    }
  }

  values.push(current)
  return values
}
