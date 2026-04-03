'use client'

import { useState } from 'react'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { MessageCircle, ChevronDown, ChevronUp } from 'lucide-react'
import DesignChat from '@/components/design/DesignChat'

interface DesignChatWrapperProps {
  designRequestId: string
  currentUserId: string
  currentUserName: string
  currentUserType?: 'designer' | 'showroom'
}

export function DesignChatWrapper({
  designRequestId,
  currentUserId,
  currentUserName,
  currentUserType = 'showroom',
}: DesignChatWrapperProps) {
  const [isExpanded, setIsExpanded] = useState(false)

  return (
    <Card>
      <CardContent className="p-0">
        <Button
          variant="ghost"
          className="w-full flex items-center justify-between p-4 hover:bg-gray-50 rounded-lg"
          onClick={() => setIsExpanded(!isExpanded)}
        >
          <div className="flex items-center gap-2">
            <MessageCircle className="h-4 w-4 text-gray-500" />
            <span className="font-semibold text-sm">Design Chat</span>
          </div>
          {isExpanded ? (
            <ChevronUp className="h-4 w-4 text-gray-400" />
          ) : (
            <ChevronDown className="h-4 w-4 text-gray-400" />
          )}
        </Button>

        {isExpanded && (
          <div className="border-t" style={{ height: 'calc(100vh - 300px)', minHeight: '400px' }}>
            <DesignChat
              designRequestId={designRequestId}
              currentUserId={currentUserId}
              currentUserName={currentUserName}
              currentUserType={currentUserType}
            />
          </div>
        )}
      </CardContent>
    </Card>
  )
}
