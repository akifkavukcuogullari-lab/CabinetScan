'use client'

import { useState } from 'react'
import { formatDistanceToNow } from 'date-fns'
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar'
import { Bot, User, ChevronDown, ChevronUp, Sparkles } from 'lucide-react'

interface ChatMessage {
  id: string
  role: 'user' | 'assistant'
  content: string
  created_at: string
}

interface ChatConversation {
  id: string
  status: string
  message_count: number
  summary: string | null
  started_at: string
  last_message_at: string
  completed_at: string | null
}

interface ChatHistorySectionProps {
  conversation: ChatConversation | null
  messages: ChatMessage[]
  assistantName: string
  assistantAvatarUrl: string | null
}

export function ChatHistorySection({
  conversation,
  messages,
  assistantName,
  assistantAvatarUrl,
}: ChatHistorySectionProps) {
  const [showAllMessages, setShowAllMessages] = useState(false)

  if (!conversation) {
    return null
  }

  const displayMessages = showAllMessages ? messages : messages.slice(0, 4)
  const hasMoreMessages = messages.length > 4

  const statusColors: Record<string, string> = {
    active: 'bg-blue-100 text-blue-800',
    completed: 'bg-green-100 text-green-800',
    abandoned: 'bg-gray-100 text-gray-800',
  }

  const getInitials = (name: string) => {
    return name
      .split(' ')
      .map((n) => n[0])
      .join('')
      .toUpperCase()
      .slice(0, 2)
  }

  return (
    <Accordion type="single" collapsible>
      <AccordionItem value="chat" className="border rounded-lg px-4">
        <AccordionTrigger className="hover:no-underline py-3">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-purple-100 rounded-lg">
              <Bot className="h-4 w-4 text-purple-600" />
            </div>
            <div className="text-left">
              <div className="flex items-center gap-2">
                <h3 className="font-semibold text-gray-900">Designer Agent Chat</h3>
                <Badge className={statusColors[conversation.status]}>
                  {conversation.status}
                </Badge>
              </div>
              <p className="text-sm text-gray-500">
                {conversation.message_count} messages with {assistantName}
              </p>
            </div>
          </div>
        </AccordionTrigger>
        <AccordionContent className="pt-1 pb-4 space-y-4">
          {/* AI Summary */}
          {conversation.summary && (
            <div className="bg-purple-50 border border-purple-200 rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <Sparkles className="h-4 w-4 text-purple-600" />
                <h4 className="font-medium text-purple-900">AI Summary</h4>
              </div>
              <p className="text-sm text-purple-800 whitespace-pre-wrap">
                {conversation.summary}
              </p>
            </div>
          )}

          {/* Messages */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h4 className="text-sm font-medium text-gray-700">Conversation</h4>
              <span className="text-xs text-gray-500">
                Started {formatDistanceToNow(new Date(conversation.started_at), { addSuffix: true })}
              </span>
            </div>

            <div className="space-y-3 max-h-[400px] overflow-y-auto">
              {displayMessages.map((message) => (
                <div
                  key={message.id}
                  className={`flex gap-3 ${
                    message.role === 'user' ? 'justify-end' : 'justify-start'
                  }`}
                >
                  {message.role === 'assistant' && (
                    <Avatar className="h-8 w-8 flex-shrink-0">
                      <AvatarImage src={assistantAvatarUrl || ''} alt={assistantName} />
                      <AvatarFallback className="bg-purple-100 text-purple-700 text-xs">
                        {getInitials(assistantName)}
                      </AvatarFallback>
                    </Avatar>
                  )}

                  <div
                    className={`max-w-[80%] rounded-lg px-3 py-2 ${
                      message.role === 'user'
                        ? 'bg-blue-600 text-white'
                        : 'bg-gray-100 text-gray-900'
                    }`}
                  >
                    <p className="text-sm whitespace-pre-wrap">{message.content}</p>
                    <p
                      className={`text-xs mt-1 ${
                        message.role === 'user' ? 'text-blue-200' : 'text-gray-500'
                      }`}
                    >
                      {formatDistanceToNow(new Date(message.created_at), { addSuffix: true })}
                    </p>
                  </div>

                  {message.role === 'user' && (
                    <div className="h-8 w-8 rounded-full bg-gray-200 flex items-center justify-center flex-shrink-0">
                      <User className="h-4 w-4 text-gray-600" />
                    </div>
                  )}
                </div>
              ))}
            </div>

            {hasMoreMessages && (
              <Button
                variant="ghost"
                size="sm"
                className="w-full text-gray-500"
                onClick={() => setShowAllMessages(!showAllMessages)}
              >
                {showAllMessages ? (
                  <>
                    <ChevronUp className="h-4 w-4 mr-2" />
                    Show Less
                  </>
                ) : (
                  <>
                    <ChevronDown className="h-4 w-4 mr-2" />
                    Show All {messages.length} Messages
                  </>
                )}
              </Button>
            )}
          </div>
        </AccordionContent>
      </AccordionItem>
    </Accordion>
  )
}
