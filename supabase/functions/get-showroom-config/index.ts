import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { supabaseAdmin } from '../_shared/supabase.ts'

interface ShowroomConfig {
  id: string
  name: string
  showroom_code: string
  branding: {
    logo_url: string | null
    logo_dark_url: string | null
    primary_color: string
    secondary_color: string
    accent_color: string
    background_color: string
    text_color: string
    welcome_message: string | null
    thank_you_message: string | null
    terms_url: string | null
    privacy_url: string | null
  }
  categories: Array<{
    id: string
    category_id: string
    name: string
    slug: string
    description: string | null
    pricing_unit: string
    icon_name: string | null
    display_order: number
    is_required: boolean
    products: Array<{
      id: string
      name: string
      description: string | null
      price: number | null
      image_url: string | null
      thumbnail_url: string | null
      display_order: number
      is_featured: boolean
      specifications: Record<string, unknown>
    }>
  }>
  subscription: {
    status: string
    plan: string | null
    video_capture: {
      enabled: boolean
      max_duration_seconds: number
      max_size_mb: number
    } | null
  }
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const url = new URL(req.url)
    const showroomCode = url.searchParams.get('code')

    if (!showroomCode) {
      return new Response(
        JSON.stringify({ error: 'Showroom code is required' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Fetch showroom by code with subscription info
    const { data: showroom, error: showroomError } = await supabaseAdmin
      .from('showrooms')
      .select(`
        id,
        name,
        showroom_code,
        subscription_status,
        subscription_plans (
          slug,
          has_video_capture,
          video_max_duration_seconds,
          video_max_size_mb
        )
      `)
      .eq('showroom_code', showroomCode.toUpperCase())
      .eq('is_active', true)
      .single()

    if (showroomError || !showroom) {
      return new Response(
        JSON.stringify({ error: 'Showroom not found' }),
        {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      )
    }

    // Fetch branding
    const { data: branding } = await supabaseAdmin
      .from('showroom_branding')
      .select('*')
      .eq('showroom_id', showroom.id)
      .single()

    // Fetch enabled categories with products
    const { data: showroomCategories } = await supabaseAdmin
      .from('showroom_categories')
      .select(`
        id,
        category_id,
        display_order,
        custom_name,
        is_required,
        categories (
          name,
          slug,
          description,
          pricing_unit,
          icon_name
        )
      `)
      .eq('showroom_id', showroom.id)
      .eq('is_enabled', true)
      .order('display_order')

    // Fetch products for this showroom
    const { data: products } = await supabaseAdmin
      .from('products')
      .select('*')
      .eq('showroom_id', showroom.id)
      .eq('is_active', true)
      .order('display_order')

    // Build categories with their products
    const categoriesWithProducts = (showroomCategories || []).map((sc: any) => {
      const categoryProducts = (products || [])
        .filter((p: any) => p.category_id === sc.category_id)
        .map((p: any) => ({
          id: p.id,
          name: p.name,
          description: p.description,
          price: p.price,
          image_url: p.image_url,
          thumbnail_url: p.thumbnail_url,
          display_order: p.display_order,
          is_featured: p.is_featured,
          specifications: p.specifications,
        }))

      return {
        id: sc.id,
        category_id: sc.category_id,
        name: sc.custom_name || sc.categories.name,
        slug: sc.categories.slug,
        description: sc.categories.description,
        pricing_unit: sc.categories.pricing_unit,
        icon_name: sc.categories.icon_name,
        display_order: sc.display_order,
        is_required: sc.is_required,
        products: categoryProducts,
      }
    })

    // Build video capture settings based on subscription
    const plan = showroom.subscription_plans as any
    const isSubscriptionActive = ['trial', 'active'].includes(showroom.subscription_status)
    const videoCapture = plan?.has_video_capture && isSubscriptionActive
      ? {
          enabled: true,
          max_duration_seconds: plan.video_max_duration_seconds || 300,
          max_size_mb: plan.video_max_size_mb || 500,
        }
      : null

    const config: ShowroomConfig = {
      id: showroom.id,
      name: showroom.name,
      showroom_code: showroom.showroom_code,
      branding: branding
        ? {
            logo_url: branding.logo_url,
            logo_dark_url: branding.logo_dark_url,
            primary_color: branding.primary_color,
            secondary_color: branding.secondary_color,
            accent_color: branding.accent_color,
            background_color: branding.background_color,
            text_color: branding.text_color,
            welcome_message: branding.welcome_message,
            thank_you_message: branding.thank_you_message,
            terms_url: branding.terms_url,
            privacy_url: branding.privacy_url,
          }
        : {
            logo_url: null,
            logo_dark_url: null,
            primary_color: '#2563EB',
            secondary_color: '#1E40AF',
            accent_color: '#3B82F6',
            background_color: '#FFFFFF',
            text_color: '#1F2937',
            welcome_message: null,
            thank_you_message: null,
            terms_url: null,
            privacy_url: null,
          },
      categories: categoriesWithProducts,
      subscription: {
        status: showroom.subscription_status,
        plan: plan?.slug || null,
        video_capture: videoCapture,
      },
    }

    return new Response(JSON.stringify(config), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    console.error('Error fetching showroom config:', error)
    return new Response(
      JSON.stringify({ error: 'Internal server error' }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    )
  }
})
