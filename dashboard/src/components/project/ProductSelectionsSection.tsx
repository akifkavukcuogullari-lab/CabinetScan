'use client'

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { Badge } from '@/components/ui/badge'
import { ShoppingBag, Box, PlusCircle } from 'lucide-react'

interface Selection {
  id: string
  category_id: string
  product_id: string
  product_name_snapshot: string
  product_price_snapshot: number | null
  pricing_unit_snapshot: string
  customer_notes?: string
  categories?: { name: string }
  products?: { name: string; image_url?: string }
}

interface AddonSelection {
  id: string
  addon_id: string
  is_selected: boolean
  quantity: number
  customer_notes?: string | null
  addon_question_snapshot: string
  addon_description_snapshot?: string | null
  addon_unit_snapshot?: string | null
  addon_price_snapshot?: number | null
  addon_image_url_snapshot?: string | null
}

interface ProductSelectionsSectionProps {
  selections?: Selection[] | null
  addonSelections?: AddonSelection[] | null
  defaultOpen?: boolean
}

export function ProductSelectionsSection({
  selections,
  addonSelections,
  defaultOpen = false
}: ProductSelectionsSectionProps) {
  const hasSelections = selections && selections.length > 0
  const hasAddons = addonSelections && addonSelections.length > 0

  if (!hasSelections && !hasAddons) {
    return null
  }

  // Group selections by category
  const groupedSelections = hasSelections
    ? selections!.reduce((acc, selection) => {
        const categoryName = selection.categories?.name || 'Other'
        if (!acc[categoryName]) {
          acc[categoryName] = []
        }
        acc[categoryName].push(selection)
        return acc
      }, {} as Record<string, Selection[]>)
    : {}

  const totalCount = (selections?.length || 0) + (addonSelections?.length || 0)

  return (
    <Accordion type="single" collapsible defaultValue={defaultOpen ? 'selections' : undefined}>
      <AccordionItem value="selections" className="border rounded-lg">
        <AccordionTrigger className="px-4 py-3 hover:no-underline">
          <div className="flex items-center gap-3 w-full">
            <ShoppingBag className="h-5 w-5 text-purple-600" />
            <div className="text-left flex-1">
              <div className="font-medium">Product Selections</div>
              <div className="text-sm text-gray-500 font-normal">
                {selections?.length || 0} products{hasAddons && `, ${addonSelections!.length} add-ons`}
              </div>
            </div>
          </div>
        </AccordionTrigger>
        <AccordionContent className="px-4 pb-4">
          <div className="space-y-4">
            {/* Product selections */}
            {Object.entries(groupedSelections).map(([categoryName, categorySelections]) => (
              <div key={categoryName}>
                <div className="text-xs font-medium text-gray-500 uppercase tracking-wider mb-2">
                  {categoryName}
                </div>
                <div className="space-y-2">
                  {categorySelections.map((selection) => (
                    <div
                      key={selection.id}
                      className="flex items-center gap-3 p-3 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors"
                    >
                      {selection.products?.image_url ? (
                        <img
                          src={selection.products.image_url}
                          alt={selection.product_name_snapshot}
                          className="w-12 h-12 object-cover rounded"
                        />
                      ) : (
                        <div className="w-12 h-12 bg-gray-200 rounded flex items-center justify-center">
                          <Box className="h-6 w-6 text-gray-400" />
                        </div>
                      )}
                      <div className="flex-1 min-w-0">
                        <p className="font-medium text-sm truncate">
                          {selection.product_name_snapshot}
                        </p>
                        {selection.customer_notes && (
                          <p className="text-xs text-gray-500 truncate">
                            Note: {selection.customer_notes}
                          </p>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}

            {/* Addon selections */}
            {hasAddons && (
              <div>
                <div className="text-xs font-medium text-gray-500 uppercase tracking-wider mb-2">
                  Add-ons
                </div>
                <div className="space-y-2">
                  {addonSelections!.map((addon) => (
                    <div
                      key={addon.id}
                      className="flex items-center gap-3 p-3 bg-purple-50 rounded-lg"
                    >
                      {addon.addon_image_url_snapshot ? (
                        <img
                          src={addon.addon_image_url_snapshot}
                          alt={addon.addon_question_snapshot}
                          className="w-12 h-12 object-cover rounded"
                        />
                      ) : (
                        <div className="w-12 h-12 bg-purple-100 rounded flex items-center justify-center">
                          <PlusCircle className="h-6 w-6 text-purple-400" />
                        </div>
                      )}
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <p className="font-medium text-sm truncate">
                            {addon.addon_question_snapshot}
                          </p>
                          <Badge variant="secondary" className="text-xs">
                            ×{addon.quantity}
                          </Badge>
                        </div>
                        {addon.customer_notes && (
                          <p className="text-xs text-gray-500 mt-1">
                            {addon.customer_notes}
                          </p>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </AccordionContent>
      </AccordionItem>
    </Accordion>
  )
}
