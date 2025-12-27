'use client'

import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { ShoppingBag, Box } from 'lucide-react'

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

interface ProductSelectionsSectionProps {
  selections?: Selection[] | null
  defaultOpen?: boolean
}

function formatPricingUnit(unit: string): string {
  return unit.replace(/_/g, ' ')
}

export function ProductSelectionsSection({
  selections,
  defaultOpen = false
}: ProductSelectionsSectionProps) {
  if (!selections || selections.length === 0) {
    return null
  }

  // Group selections by category
  const groupedSelections = selections.reduce((acc, selection) => {
    const categoryName = selection.categories?.name || 'Other'
    if (!acc[categoryName]) {
      acc[categoryName] = []
    }
    acc[categoryName].push(selection)
    return acc
  }, {} as Record<string, Selection[]>)

  // Calculate total estimate
  const totalEstimate = selections.reduce((sum, selection) => {
    return sum + (selection.product_price_snapshot || 0)
  }, 0)

  return (
    <Accordion type="single" collapsible defaultValue={defaultOpen ? 'selections' : undefined}>
      <AccordionItem value="selections" className="border rounded-lg">
        <AccordionTrigger className="px-4 py-3 hover:no-underline">
          <div className="flex items-center gap-3 w-full">
            <ShoppingBag className="h-5 w-5 text-purple-600" />
            <div className="text-left flex-1">
              <div className="font-medium">Product Selections</div>
              <div className="text-sm text-gray-500 font-normal">
                {selections.length} products selected
              </div>
            </div>
            {totalEstimate > 0 && (
              <div className="text-right mr-2">
                <div className="text-lg font-bold text-green-600">
                  ${totalEstimate.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                </div>
                <div className="text-xs text-gray-500">Est. Total</div>
              </div>
            )}
          </div>
        </AccordionTrigger>
        <AccordionContent className="px-4 pb-4">
          <div className="space-y-4">
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
                      <div className="text-right flex-shrink-0">
                        {selection.product_price_snapshot !== null && (
                          <p className="font-medium text-sm">
                            ${selection.product_price_snapshot.toFixed(2)}
                          </p>
                        )}
                        <p className="text-xs text-gray-500">
                          {formatPricingUnit(selection.pricing_unit_snapshot)}
                        </p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}

            {/* Total */}
            {totalEstimate > 0 && (
              <div className="pt-3 mt-3 border-t flex items-center justify-between">
                <span className="font-medium">Estimated Total</span>
                <span className="text-xl font-bold text-green-600">
                  ${totalEstimate.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                </span>
              </div>
            )}
          </div>
        </AccordionContent>
      </AccordionItem>
    </Accordion>
  )
}
