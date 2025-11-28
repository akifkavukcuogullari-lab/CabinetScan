'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { ArrowLeft } from 'lucide-react'

const pricingUnits = [
  { value: 'per_linear_ft', label: 'Per Linear Foot' },
  { value: 'per_sq_ft', label: 'Per Square Foot' },
  { value: 'per_piece', label: 'Per Piece' },
  { value: 'per_cabinet', label: 'Per Cabinet' },
  { value: 'flat', label: 'Flat Rate' },
  { value: 'none', label: 'No Pricing' },
]

function generateSlug(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
}

export default function NewCategoryPage() {
  const router = useRouter()
  const supabase = createClient()

  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [formData, setFormData] = useState({
    name: '',
    slug: '',
    description: '',
    pricingUnit: 'none',
    iconName: '',
    displayOrder: '0',
  })

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>
  ) => {
    const { name, value } = e.target
    setFormData((prev) => ({
      ...prev,
      [name]: value,
      // Auto-generate slug from name
      ...(name === 'name' ? { slug: generateSlug(value) } : {}),
    }))
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    setError(null)

    try {
      const { error: insertError } = await supabase.from('categories').insert({
        name: formData.name,
        slug: formData.slug || generateSlug(formData.name),
        description: formData.description || null,
        pricing_unit: formData.pricingUnit,
        icon_name: formData.iconName || null,
        display_order: parseInt(formData.displayOrder) || 0,
        is_active: true,
      })

      if (insertError) throw insertError

      router.push('/admin/categories')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create category')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <div className="flex items-center gap-4">
        <Link href="/admin/categories">
          <Button variant="ghost" size="icon">
            <ArrowLeft className="h-5 w-5" />
          </Button>
        </Link>
        <div>
          <h1 className="text-2xl font-bold">Create Category</h1>
          <p className="text-gray-500">Add a new product category</p>
        </div>
      </div>

      <form onSubmit={handleSubmit}>
        <Card>
          <CardHeader>
            <CardTitle>Category Details</CardTitle>
            <CardDescription>
              Categories define product types that showrooms can offer
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
                placeholder="Cabinet Model"
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
                placeholder="cabinet-model"
              />
              <p className="text-xs text-gray-500">
                URL-friendly identifier. Auto-generated from name if left empty.
              </p>
            </div>

            <div className="space-y-2">
              <Label htmlFor="description">Description</Label>
              <Input
                id="description"
                name="description"
                value={formData.description}
                onChange={handleChange}
                placeholder="Cabinet style and configuration"
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
              <p className="text-xs text-gray-500">
                How products in this category are priced
              </p>
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="iconName">SF Symbol Icon</Label>
                <Input
                  id="iconName"
                  name="iconName"
                  value={formData.iconName}
                  onChange={handleChange}
                  placeholder="cabinet"
                />
                <p className="text-xs text-gray-500">
                  iOS SF Symbol name for the category icon
                </p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="displayOrder">Display Order</Label>
                <Input
                  id="displayOrder"
                  name="displayOrder"
                  type="number"
                  value={formData.displayOrder}
                  onChange={handleChange}
                  placeholder="0"
                />
              </div>
            </div>
          </CardContent>
        </Card>

        <div className="flex justify-end gap-4 mt-6">
          <Link href="/admin/categories">
            <Button variant="outline" type="button">
              Cancel
            </Button>
          </Link>
          <Button type="submit" disabled={loading}>
            {loading ? 'Creating...' : 'Create Category'}
          </Button>
        </div>
      </form>
    </div>
  )
}
