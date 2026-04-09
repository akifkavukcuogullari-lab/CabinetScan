import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Auth — super admin only
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Authorization required' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const token = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Invalid token' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verify super admin
    const { data: admin } = await supabaseAdmin
      .from('admins')
      .select('id')
      .eq('user_id', user.id)
      .single()

    if (!admin) {
      return new Response(
        JSON.stringify({ error: 'Super admin access required' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { showroom_id, amount_cents, type, notes } = await req.json()

    if (!showroom_id || !amount_cents || !type) {
      return new Response(
        JSON.stringify({ error: 'showroom_id, amount_cents, and type are required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!['adjustment', 'refund', 'plan_bonus'].includes(type)) {
      return new Response(
        JSON.stringify({ error: 'type must be adjustment, refund, or plan_bonus' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Call the add_showroom_credit function
    const { data, error } = await supabaseAdmin.rpc('add_showroom_credit', {
      p_showroom_id: showroom_id,
      p_amount_cents: amount_cents,
      p_type: type,
      p_performed_by: user.id,
      p_notes: notes || `Manual ${type} by admin`,
    })

    if (error) {
      console.error('[CREDIT_ADMIN] RPC error:', error)
      return new Response(
        JSON.stringify({ error: 'Failed to adjust credits' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const result = data?.[0] || data
    console.log(`[CREDIT_ADMIN] ${type} $${(amount_cents / 100).toFixed(2)} for showroom ${showroom_id}`)

    return new Response(
      JSON.stringify({
        success: true,
        new_balance_cents: result?.new_balance_cents,
        transaction_id: result?.transaction_id,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('[CREDIT_ADMIN] Error:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
