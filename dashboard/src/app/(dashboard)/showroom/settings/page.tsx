'use client'

import { useState, useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Separator } from '@/components/ui/separator'
import { Switch } from '@/components/ui/switch'

interface Category {
  id: string
  name: string
  slug: string
  pricing_unit: string
  display_order: number
}

interface ShowroomCategory {
  id: string
  category_id: string
  is_enabled: boolean
  display_order: number
  is_required: boolean
  custom_name: string | null
}

export default function SettingsPage() {
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)
  const [showroomId, setShowroomId] = useState<string | null>(null)
  const [showroom, setShowroom] = useState<any>(null)
  const [categories, setCategories] = useState<Category[]>([])
  const [showroomCategories, setShowroomCategories] = useState<ShowroomCategory[]>([])

  useEffect(() => {
    async function loadData() {
      const { data: { user } } = await supabase.auth.getUser()
      if (!user) return

      const { data: showroomUser } = await supabase
        .from('showroom_users')
        .select('showroom_id')
        .eq('user_id', user.id)
        .single()

      if (!showroomUser) return

      setShowroomId(showroomUser.showroom_id)

      // Load showroom details
      const { data: showroomData } = await supabase
        .from('showrooms')
        .select('*')
        .eq('id', showroomUser.showroom_id)
        .single()

      if (showroomData) setShowroom(showroomData)

      // Load all categories
      const { data: categoriesData } = await supabase
        .from('categories')
        .select('*')
        .eq('is_active', true)
        .order('display_order')

      if (categoriesData) setCategories(categoriesData)

      // Load showroom categories
      const { data: showroomCategoriesData } = await supabase
        .from('showroom_categories')
        .select('*')
        .eq('showroom_id', showroomUser.showroom_id)

      if (showroomCategoriesData) setShowroomCategories(showroomCategoriesData)

      setLoading(false)
    }

    loadData()
  }, [supabase])

  const getCategorySettings = (categoryId: string): ShowroomCategory | undefined => {
    return showroomCategories.find((sc) => sc.category_id === categoryId)
  }

  const toggleCategory = async (categoryId: string, enabled: boolean) => {
    if (!showroomId) return

    const existing = getCategorySettings(categoryId)

    if (existing) {
      // Update existing
      await supabase
        .from('showroom_categories')
        .update({ is_enabled: enabled })
        .eq('id', existing.id)

      setShowroomCategories((prev) =>
        prev.map((sc) =>
          sc.category_id === categoryId ? { ...sc, is_enabled: enabled } : sc
        )
      )
    } else {
      // Create new
      const category = categories.find((c) => c.id === categoryId)
      const { data } = await supabase
        .from('showroom_categories')
        .insert({
          showroom_id: showroomId,
          category_id: categoryId,
          is_enabled: enabled,
          display_order: category?.display_order || 0,
        })
        .select()
        .single()

      if (data) {
        setShowroomCategories((prev) => [...prev, data])
      }
    }
  }

  const toggleRequired = async (categoryId: string, required: boolean) => {
    const existing = getCategorySettings(categoryId)
    if (!existing) return

    await supabase
      .from('showroom_categories')
      .update({ is_required: required })
      .eq('id', existing.id)

    setShowroomCategories((prev) =>
      prev.map((sc) =>
        sc.category_id === categoryId ? { ...sc, is_required: required } : sc
      )
    )
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-gray-500">Loading...</p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Settings</h1>
        <p className="text-gray-500">Configure your showroom settings</p>
      </div>

      {/* Showroom Info */}
      <Card>
        <CardHeader>
          <CardTitle>Showroom Information</CardTitle>
          <CardDescription>Your showroom details</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label className="text-gray-500">Showroom Name</Label>
              <p className="font-medium">{showroom?.name}</p>
            </div>
            <div>
              <Label className="text-gray-500">Showroom Code</Label>
              <p className="font-mono text-lg font-bold">{showroom?.showroom_code}</p>
            </div>
          </div>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <Label className="text-gray-500">Email</Label>
              <p>{showroom?.email}</p>
            </div>
            <div>
              <Label className="text-gray-500">Phone</Label>
              <p>{showroom?.phone || '-'}</p>
            </div>
          </div>
          <div>
            <Label className="text-gray-500">Subscription Status</Label>
            <div className="mt-1">
              <Badge
                className={
                  showroom?.subscription_status === 'active'
                    ? 'bg-green-100 text-green-800'
                    : showroom?.subscription_status === 'trial'
                    ? 'bg-yellow-100 text-yellow-800'
                    : 'bg-gray-100 text-gray-800'
                }
              >
                {showroom?.subscription_status}
              </Badge>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Categories */}
      <Card>
        <CardHeader>
          <CardTitle>Product Categories</CardTitle>
          <CardDescription>
            Enable or disable categories for your showroom. Customers will only see enabled
            categories in the iOS app.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {categories.map((category) => {
              const settings = getCategorySettings(category.id)
              const isEnabled = settings?.is_enabled ?? false
              const isRequired = settings?.is_required ?? false

              return (
                <div
                  key={category.id}
                  className="flex items-center justify-between py-3 border-b last:border-0"
                >
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <span className="font-medium">{category.name}</span>
                      <Badge variant="outline" className="text-xs">
                        {category.pricing_unit.replace('_', ' ')}
                      </Badge>
                    </div>
                    <p className="text-sm text-gray-500">{category.slug}</p>
                  </div>

                  <div className="flex items-center gap-6">
                    <div className="flex items-center gap-2">
                      <Label htmlFor={`required-${category.id}`} className="text-sm text-gray-500">
                        Required
                      </Label>
                      <Switch
                        id={`required-${category.id}`}
                        checked={isRequired}
                        onCheckedChange={(checked) => toggleRequired(category.id, checked)}
                        disabled={!isEnabled}
                      />
                    </div>

                    <div className="flex items-center gap-2">
                      <Label htmlFor={`enabled-${category.id}`} className="text-sm text-gray-500">
                        Enabled
                      </Label>
                      <Switch
                        id={`enabled-${category.id}`}
                        checked={isEnabled}
                        onCheckedChange={(checked) => toggleCategory(category.id, checked)}
                      />
                    </div>
                  </div>
                </div>
              )
            })}
          </div>
        </CardContent>
      </Card>

      {/* Danger Zone */}
      <Card className="border-red-200">
        <CardHeader>
          <CardTitle className="text-red-600">Danger Zone</CardTitle>
          <CardDescription>Irreversible actions for your showroom</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex items-center justify-between">
            <div>
              <p className="font-medium">Delete all products</p>
              <p className="text-sm text-gray-500">
                Remove all products from your showroom. This cannot be undone.
              </p>
            </div>
            <Button variant="destructive" size="sm">
              Delete Products
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
