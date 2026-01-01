'use client'

import { useState } from 'react'
import { Switch } from '@/components/ui/switch'
import { Label } from '@/components/ui/label'
import { createClient } from '@/lib/supabase/client'
import { useRouter } from 'next/navigation'

interface CategoryPriceToggleProps {
  showroomCategoryId: string
  categoryName: string
  initialValue: boolean
}

export function CategoryPriceToggle({
  showroomCategoryId,
  categoryName,
  initialValue
}: CategoryPriceToggleProps) {
  const [showPrice, setShowPrice] = useState(initialValue)
  const [isUpdating, setIsUpdating] = useState(false)
  const router = useRouter()
  const supabase = createClient()

  const handleToggle = async (checked: boolean) => {
    setShowPrice(checked)
    setIsUpdating(true)

    try {
      const { error } = await supabase
        .from('showroom_categories')
        .update({ show_price_to_customer: checked })
        .eq('id', showroomCategoryId)

      if (error) {
        console.error('Error updating price visibility:', error)
        setShowPrice(!checked) // Revert on error
      } else {
        router.refresh()
      }
    } catch (error) {
      console.error('Error updating price visibility:', error)
      setShowPrice(!checked) // Revert on error
    } finally {
      setIsUpdating(false)
    }
  }

  return (
    <div className="flex items-center gap-2">
      <Switch
        id={`show-price-${showroomCategoryId}`}
        checked={showPrice}
        onCheckedChange={handleToggle}
        disabled={isUpdating}
      />
      <Label
        htmlFor={`show-price-${showroomCategoryId}`}
        className="text-sm text-gray-600 cursor-pointer"
      >
        Show prices in iOS app
      </Label>
    </div>
  )
}
