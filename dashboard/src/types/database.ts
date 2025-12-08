export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      admins: {
        Row: {
          id: string
          user_id: string
          email: string
          full_name: string
          is_active: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          user_id: string
          email: string
          full_name: string
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          user_id?: string
          email?: string
          full_name?: string
          is_active?: boolean
          created_at?: string
          updated_at?: string
        }
      }
      categories: {
        Row: {
          id: string
          name: string
          slug: string
          description: string | null
          pricing_unit: 'per_linear_ft' | 'per_sq_ft' | 'per_piece' | 'per_cabinet' | 'flat' | 'none'
          display_order: number
          is_active: boolean
          icon_name: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          name: string
          slug: string
          description?: string | null
          pricing_unit?: 'per_linear_ft' | 'per_sq_ft' | 'per_piece' | 'per_cabinet' | 'flat' | 'none'
          display_order?: number
          is_active?: boolean
          icon_name?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          name?: string
          slug?: string
          description?: string | null
          pricing_unit?: 'per_linear_ft' | 'per_sq_ft' | 'per_piece' | 'per_cabinet' | 'flat' | 'none'
          display_order?: number
          is_active?: boolean
          icon_name?: string | null
          created_at?: string
          updated_at?: string
        }
      }
      showrooms: {
        Row: {
          id: string
          name: string
          slug: string
          showroom_code: string
          email: string
          phone: string | null
          address_line1: string | null
          address_line2: string | null
          city: string | null
          state: string | null
          postal_code: string | null
          country: string
          timezone: string
          currency: string
          tax_rate: number
          subscription_status: 'trial' | 'active' | 'past_due' | 'canceled' | 'suspended'
          trial_ends_at: string | null
          subscription_plan: string | null
          stripe_customer_id: string | null
          webhook_url: string | null
          quote_webhook_url: string | null
          is_active: boolean
          created_at: string
          updated_at: string
          created_by: string | null
        }
        Insert: {
          id?: string
          name: string
          slug: string
          showroom_code: string
          email: string
          phone?: string | null
          address_line1?: string | null
          address_line2?: string | null
          city?: string | null
          state?: string | null
          postal_code?: string | null
          country?: string
          timezone?: string
          currency?: string
          tax_rate?: number
          subscription_status?: 'trial' | 'active' | 'past_due' | 'canceled' | 'suspended'
          trial_ends_at?: string | null
          subscription_plan?: string | null
          stripe_customer_id?: string | null
          webhook_url?: string | null
          quote_webhook_url?: string | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
          created_by?: string | null
        }
        Update: {
          id?: string
          name?: string
          slug?: string
          showroom_code?: string
          email?: string
          phone?: string | null
          address_line1?: string | null
          address_line2?: string | null
          city?: string | null
          state?: string | null
          postal_code?: string | null
          country?: string
          timezone?: string
          currency?: string
          tax_rate?: number
          subscription_status?: 'trial' | 'active' | 'past_due' | 'canceled' | 'suspended'
          trial_ends_at?: string | null
          subscription_plan?: string | null
          stripe_customer_id?: string | null
          webhook_url?: string | null
          quote_webhook_url?: string | null
          is_active?: boolean
          created_at?: string
          updated_at?: string
          created_by?: string | null
        }
      }
      showroom_branding: {
        Row: {
          id: string
          showroom_id: string
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
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          showroom_id: string
          logo_url?: string | null
          logo_dark_url?: string | null
          primary_color?: string
          secondary_color?: string
          accent_color?: string
          background_color?: string
          text_color?: string
          welcome_message?: string | null
          thank_you_message?: string | null
          terms_url?: string | null
          privacy_url?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          showroom_id?: string
          logo_url?: string | null
          logo_dark_url?: string | null
          primary_color?: string
          secondary_color?: string
          accent_color?: string
          background_color?: string
          text_color?: string
          welcome_message?: string | null
          thank_you_message?: string | null
          terms_url?: string | null
          privacy_url?: string | null
          created_at?: string
          updated_at?: string
        }
      }
      showroom_users: {
        Row: {
          id: string
          user_id: string
          showroom_id: string
          email: string
          full_name: string
          role: string
          is_primary: boolean
          is_active: boolean
          created_at: string
          updated_at: string
          invited_by: string | null
        }
        Insert: {
          id?: string
          user_id: string
          showroom_id: string
          email: string
          full_name: string
          role?: string
          is_primary?: boolean
          is_active?: boolean
          created_at?: string
          updated_at?: string
          invited_by?: string | null
        }
        Update: {
          id?: string
          user_id?: string
          showroom_id?: string
          email?: string
          full_name?: string
          role?: string
          is_primary?: boolean
          is_active?: boolean
          created_at?: string
          updated_at?: string
          invited_by?: string | null
        }
      }
      showroom_categories: {
        Row: {
          id: string
          showroom_id: string
          category_id: string
          is_enabled: boolean
          display_order: number
          custom_name: string | null
          is_required: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          showroom_id: string
          category_id: string
          is_enabled?: boolean
          display_order?: number
          custom_name?: string | null
          is_required?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          showroom_id?: string
          category_id?: string
          is_enabled?: boolean
          display_order?: number
          custom_name?: string | null
          is_required?: boolean
          created_at?: string
          updated_at?: string
        }
      }
      products: {
        Row: {
          id: string
          showroom_id: string
          category_id: string
          name: string
          description: string | null
          sku: string | null
          price: number | null
          image_url: string | null
          thumbnail_url: string | null
          additional_images: string[] | null
          display_order: number
          is_active: boolean
          is_featured: boolean
          has_variants: boolean
          specifications: Json
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          showroom_id: string
          category_id: string
          name: string
          description?: string | null
          sku?: string | null
          price?: number | null
          image_url?: string | null
          thumbnail_url?: string | null
          additional_images?: string[] | null
          display_order?: number
          is_active?: boolean
          is_featured?: boolean
          has_variants?: boolean
          specifications?: Json
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          showroom_id?: string
          category_id?: string
          name?: string
          description?: string | null
          sku?: string | null
          price?: number | null
          image_url?: string | null
          thumbnail_url?: string | null
          additional_images?: string[] | null
          display_order?: number
          is_active?: boolean
          is_featured?: boolean
          has_variants?: boolean
          specifications?: Json
          created_at?: string
          updated_at?: string
        }
      }
      product_variants: {
        Row: {
          id: string
          product_id: string
          name: string
          color_code: string | null
          price: number | null
          image_url: string | null
          thumbnail_url: string | null
          display_order: number
          is_active: boolean
          is_default: boolean
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          product_id: string
          name: string
          color_code?: string | null
          price?: number | null
          image_url?: string | null
          thumbnail_url?: string | null
          display_order?: number
          is_active?: boolean
          is_default?: boolean
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          product_id?: string
          name?: string
          color_code?: string | null
          price?: number | null
          image_url?: string | null
          thumbnail_url?: string | null
          display_order?: number
          is_active?: boolean
          is_default?: boolean
          created_at?: string
          updated_at?: string
        }
      }
      customers: {
        Row: {
          id: string
          showroom_id: string
          phone: string
          phone_normalized: string
          first_name: string
          last_name: string
          email: string | null
          customer_type: 'homeowner' | 'contractor'
          address_line1: string | null
          city: string | null
          state: string | null
          zip_code: string | null
          notes: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          showroom_id: string
          phone: string
          phone_normalized?: string
          first_name: string
          last_name: string
          email?: string | null
          customer_type?: 'homeowner' | 'contractor'
          address_line1?: string | null
          city?: string | null
          state?: string | null
          zip_code?: string | null
          notes?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          showroom_id?: string
          phone?: string
          phone_normalized?: string
          first_name?: string
          last_name?: string
          email?: string | null
          customer_type?: 'homeowner' | 'contractor'
          address_line1?: string | null
          city?: string | null
          state?: string | null
          zip_code?: string | null
          notes?: string | null
          created_at?: string
          updated_at?: string
        }
      }
      projects: {
        Row: {
          id: string
          showroom_id: string
          customer_id: string | null
          reference_number: string
          customer_first_name: string
          customer_last_name: string
          customer_email: string
          customer_phone: string | null
          project_name: string
          project_notes: string | null
          status: 'draft' | 'submitted' | 'in_review' | 'quoted' | 'accepted' | 'rejected' | 'completed'
          submitted_at: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          device_model: string | null
          ios_version: string | null
          app_version: string | null
          end_client_first_name: string | null
          end_client_last_name: string | null
          end_client_phone: string | null
          end_client_email: string | null
          end_client_address: string | null
          webhook_payload: Json | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          showroom_id: string
          customer_id?: string | null
          reference_number: string
          customer_first_name: string
          customer_last_name: string
          customer_email: string
          customer_phone?: string | null
          project_name: string
          project_notes?: string | null
          status?: 'draft' | 'submitted' | 'in_review' | 'quoted' | 'accepted' | 'rejected' | 'completed'
          submitted_at?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          device_model?: string | null
          ios_version?: string | null
          app_version?: string | null
          end_client_first_name?: string | null
          end_client_last_name?: string | null
          end_client_phone?: string | null
          end_client_email?: string | null
          end_client_address?: string | null
          webhook_payload?: Json | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          showroom_id?: string
          customer_id?: string | null
          reference_number?: string
          customer_first_name?: string
          customer_last_name?: string
          customer_email?: string
          customer_phone?: string | null
          project_name?: string
          project_notes?: string | null
          status?: 'draft' | 'submitted' | 'in_review' | 'quoted' | 'accepted' | 'rejected' | 'completed'
          submitted_at?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          device_model?: string | null
          ios_version?: string | null
          app_version?: string | null
          end_client_first_name?: string | null
          end_client_last_name?: string | null
          end_client_phone?: string | null
          end_client_email?: string | null
          end_client_address?: string | null
          webhook_payload?: Json | null
          created_at?: string
          updated_at?: string
        }
      }
      project_measurements: {
        Row: {
          id: string
          project_id: string
          room_name: string
          room_type: string | null
          roomplan_data: Json
          total_linear_ft: number | null
          total_sq_ft: number | null
          wall_count: number | null
          window_count: number | null
          door_count: number | null
          measurements: Json
          usdz_file_url: string | null
          preview_image_url: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          project_id: string
          room_name?: string
          room_type?: string | null
          roomplan_data: Json
          total_linear_ft?: number | null
          total_sq_ft?: number | null
          wall_count?: number | null
          window_count?: number | null
          door_count?: number | null
          measurements?: Json
          usdz_file_url?: string | null
          preview_image_url?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          project_id?: string
          room_name?: string
          room_type?: string | null
          roomplan_data?: Json
          total_linear_ft?: number | null
          total_sq_ft?: number | null
          wall_count?: number | null
          window_count?: number | null
          door_count?: number | null
          measurements?: Json
          usdz_file_url?: string | null
          preview_image_url?: string | null
          created_at?: string
          updated_at?: string
        }
      }
      project_selections: {
        Row: {
          id: string
          project_id: string
          category_id: string
          product_id: string
          quantity: number
          product_name_snapshot: string
          product_price_snapshot: number | null
          pricing_unit_snapshot: 'per_linear_ft' | 'per_sq_ft' | 'per_piece' | 'per_cabinet' | 'flat' | 'none'
          customer_notes: string | null
          created_at: string
        }
        Insert: {
          id?: string
          project_id: string
          category_id: string
          product_id: string
          quantity?: number
          product_name_snapshot: string
          product_price_snapshot?: number | null
          pricing_unit_snapshot: 'per_linear_ft' | 'per_sq_ft' | 'per_piece' | 'per_cabinet' | 'flat' | 'none'
          customer_notes?: string | null
          created_at?: string
        }
        Update: {
          id?: string
          project_id?: string
          category_id?: string
          product_id?: string
          quantity?: number
          product_name_snapshot?: string
          product_price_snapshot?: number | null
          pricing_unit_snapshot?: 'per_linear_ft' | 'per_sq_ft' | 'per_piece' | 'per_cabinet' | 'flat' | 'none'
          customer_notes?: string | null
          created_at?: string
        }
      }
      quote_emails: {
        Row: {
          id: string
          project_id: string
          recipient_email: string
          subject: string
          body_html: string
          body_text: string | null
          customer_name: string | null
          reference_number: string | null
          grand_total: string | null
          quote_summary: Json | null
          status: string
          sent_at: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id?: string
          project_id: string
          recipient_email: string
          subject: string
          body_html: string
          body_text?: string | null
          customer_name?: string | null
          reference_number?: string | null
          grand_total?: string | null
          quote_summary?: Json | null
          status?: string
          sent_at?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          id?: string
          project_id?: string
          recipient_email?: string
          subject?: string
          body_html?: string
          body_text?: string | null
          customer_name?: string | null
          reference_number?: string | null
          grand_total?: string | null
          quote_summary?: Json | null
          status?: string
          sent_at?: string | null
          created_at?: string
          updated_at?: string
        }
      }
    }
    Functions: {
      is_super_admin: {
        Args: Record<PropertyKey, never>
        Returns: boolean
      }
      get_user_showroom_ids: {
        Args: Record<PropertyKey, never>
        Returns: string[]
      }
      has_showroom_access: {
        Args: { p_showroom_id: string }
        Returns: boolean
      }
      get_customer_stats: {
        Args: { p_showroom_id: string }
        Returns: {
          total_customers: number
          homeowner_count: number
          contractor_count: number
          customers_this_month: number
        }[]
      }
    }
    Enums: {
      user_role: 'super_admin' | 'showroom_owner'
      project_status: 'draft' | 'submitted' | 'in_review' | 'quoted' | 'accepted' | 'rejected' | 'completed'
      pricing_unit: 'per_linear_ft' | 'per_sq_ft' | 'per_piece' | 'per_cabinet' | 'flat' | 'none'
      subscription_status: 'trial' | 'active' | 'past_due' | 'canceled' | 'suspended'
      customer_type: 'homeowner' | 'contractor'
    }
  }
}
