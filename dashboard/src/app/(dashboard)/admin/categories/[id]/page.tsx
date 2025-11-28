'use client'

import { useState, useEffect, use } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { ArrowLeft, Trash2 } from 'lucide-react'

const pricingUnits = [
  { value: 'per_linear_ft', label: 'Per Linear Foot' },
  { value: 'per_sq_ft', label: 'Per Square Foot' },
  { value: 'per_piece', label: 'Per Piece' },
  { value: 'per_cabinet', label: 'Per Cabinet' },
  { value: 'flat', label: 'Flat Rate' },
  { value: 'none', label: 'No Pricing' },
]

interface EditCategoryPageProps {
  params: Promise<{ id: string }>
}

export default function EditCategoryPage({ params }: EditCategoryPageProps) {
  const { id } = use(params)
  const router = useRouter()
  const supabase = createClient()

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [formData, setFormData] = useState({
    name: '',
    slug: '',
    description: '',
    pricingUnit: 'none',
    iconName: '',
    displayOrder: '0',
    isActive: true,
  })

  useEffect(() => {
    async function loadCategory() {
      const { data, error: fetchError } = await supabase
        .from('categories')
        .select('*')
        .eq('id', id)
        .single()

      if (fetchError || !data) {
        setError('Category not found')
        setLoading(false)
        return
      }

      const category = data as {
        name: string
        slug: string
        description: string | null
        pricing_unit: string
        icon_name: string | null
        display_order: number
        is_active: boolean
      }

      setFormData({
        name: category.name,
        slug: category.slug,
        description: category.description || '',
        pricingUnit: category.pricing_unit,
        iconName: category.icon_name || '',
        displayOrder: category.display_order.toString(),
        isActive: category.is_active,
      })
      setLoading(false)
    }

    loadCategory()
  }, [id, supabase])

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>
  ) => {
    const { name, value, type } = e.target
    setFormData((prev) => ({
      ...prev,
      [name]: type === 'checkbox' ? (e.target as HTMLInputElement).checked : value,
    }))
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setError(null)

    try {
      const { error: updateError } = await supabase
        .from('categories')
        .update({
          name: formData.name,
          slug: formData.slug,
          description: formData.description || null,
          pricing_unit: formData.pricingUnit,
          icon_name: formData.iconName || null,
          display_order: parseInt(formData.displayOrder) || 0,
          is_active: formData.isActive,
        })
        .eq('id', id)

      if (updateError) throw updateError

      router.push('/admin/categories')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to update category')
    } finally {
      setSaving(false)
    }
  }

  const handleDelete = async () => {
    if (!confirm('Are you sure you want to delete this category?')) return

    try {
      const { error: deleteError } = await supabase
        .from('categories')
        .delete()
        .eq('id', id)

      if (deleteError) throw deleteError

      router.push('/admin/categories')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to delete category')
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-gray-500">Loading...</p>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div className="flex items-center gap-4">
        <Link href="/admin/categories">
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div className="flex-1">
          <h1 className="text-2xl font-bold">Edit Category</h1>
          <p className="text-gray-500">Update category details</p>
        </div>
        <Button variant="destructive" size="icon" onClick={handleDelete}>
          <Trash2 className="h-5 w-5" />
        </Button>
      </div>

      <form onSubmit={handleSubmit}>
        <Card>
          <CardHeader>
            <CardTitle>Category Details</CardTitle>
            <CardDescription>
              Update the category information
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {error && (
              <div className="p-3 text-sm text-red-600 bg-red-50 rounded-md">
                {error}
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="name">Category Name *</Label>
              <Input
                id="name"
                name="name"
                value={formData.name}
                onChange={handleChange}
                required
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="slug">Slug</Label>
              <Input
                id="slug"
                name="slug"
                value={formData.slug}
                onChange={handleChange}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="description">Description</Label>
              <Input
                id="description"
                name="description"
                value={formData.description}
                onChange={handleChange}
              />
            </div>

            <div className="space-y-2">
              <Label htmlFor="pricingUnit">Pricing Unit</Label>
              <select
                id="pricingUnit"
                name="pricingUnit"
                value={formData.pricingUnit}
                onChange={handleChange}
                className="w-full h-10 px-3 rounded-md border border-input bg-background text-sm"
              >
                {pricingUnits.map((unit) => (
                  <option key={unit.value} value={unit.value}>
                    {unit.label}
                  </option>
                ))}
              </select>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="iconName">SF Symbol Icon</Label>
                <Input
                  id="iconName"
                  name="iconName"
                  value={formData.iconName}
                  onChange={handleChange}
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="displayOrder">Display Order</Label>
                <Input
                  id="displayOrder"
                  name="displayOrder"
                  type="number"
                  value={formData.displayOrder}
                  onChange={handleChange}
                />
              </div>
            </div>

            <div className="flex items-center gap-2">
              <input
                type="checkbox"
                id="isActive"
                name="isActive"
                checked={formData.isActive}
                onChange={handleChange}
                className="h-4 w-4 rounded border-gray-300"
              />
              <Label htmlFor="isActive">Active</Label>
            </div>
          </CardContent>
        </Card>

        <div className="flex justify-end gap-4 mt-6">
          <Link href="/admin/categories">
            <Button variant="outline" type="button">
              Cancel
            </Button>
          </Link>
          <Button type="submit" disabled={saving}>
            {saving ? 'Saving...' : 'Save Changes'}
          </Button>
        </div>
      </form>
    </div>
  )
}
