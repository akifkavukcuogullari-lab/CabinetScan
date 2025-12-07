'use client'

import { useState } from 'react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Webhook, ChevronDown, ChevronRight } from 'lucide-react'

interface WebhookPayloadViewerProps {
  payload: Record<string, unknown>
}

export function WebhookPayloadViewer({ payload }: WebhookPayloadViewerProps) {
  const [isExpanded, setIsExpanded] = useState(false)

  const jsonString = JSON.stringify(payload, null, 2)

  return (
    <Card>
      <CardHeader className="pb-3">
        <button
          onClick={() => setIsExpanded(!isExpanded)}
          className="flex items-center justify-between w-full text-left"
        >
          <div className="flex items-center gap-2">
            <Webhook className="h-5 w-5 text-purple-600" />
            <CardTitle>Webhook Payload</CardTitle>
          </div>
          <div className="flex items-center gap-2">
            {isExpanded ? (
              <ChevronDown className="h-5 w-5 text-gray-500" />
            ) : (
              <ChevronRight className="h-5 w-5 text-gray-500" />
            )}
          </div>
        </button>
        <CardDescription>
          JSON data sent to the showroom&apos;s webhook URL when this project was submitted
        </CardDescription>
      </CardHeader>
      {isExpanded && (
        <CardContent>
          <pre
            className="bg-gray-50 border rounded-lg p-4 overflow-x-auto text-xs font-mono max-h-[600px] overflow-y-auto select-all cursor-text"
          >
            {jsonString}
          </pre>
          <p className="text-xs text-gray-500 mt-2">
            Tip: Select all text (Cmd+A / Ctrl+A) and copy (Cmd+C / Ctrl+C)
          </p>
        </CardContent>
      )}
    </Card>
  )
}
