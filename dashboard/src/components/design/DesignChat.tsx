"use client"

import { useState, useEffect, useRef, useCallback } from "react"
import { format, isToday, isYesterday, isSameDay } from "date-fns"
import { MessageSquareIcon } from "lucide-react"
import { createClient } from "@/lib/supabase/client"
import { Skeleton } from "@/components/ui/skeleton"
import { ChatMessageBubble } from "./ChatMessageBubble"
import { ChatInput } from "./ChatInput"
import { toast } from "sonner"
import { sendDesignNotification } from "@/lib/design-notifications"

interface ChatMessage {
  id: string
  design_request_id: string
  sender_type: "designer" | "showroom"
  sender_id: string
  sender_name: string
  message_type: "text" | "image" | "audio" | "file"
  content: string | null
  file_url: string | null
  file_name: string | null
  file_size_bytes: number | null
  is_read: boolean
  read_at: string | null
  created_at: string
}

interface DesignChatProps {
  designRequestId: string
  currentUserType: "designer" | "showroom"
  currentUserId: string
  currentUserName: string
}

function formatDateSeparator(dateStr: string): string {
  const date = new Date(dateStr)
  if (isToday(date)) return "Today"
  if (isYesterday(date)) return "Yesterday"
  return format(date, "MMMM d, yyyy")
}

function MessagesSkeleton() {
  return (
    <div className="flex flex-col gap-4 p-4">
      <div className="self-start flex flex-col gap-1 max-w-[60%]">
        <Skeleton className="h-3 w-16" />
        <Skeleton className="h-10 w-48 rounded-2xl" />
      </div>
      <div className="self-end flex flex-col gap-1 items-end max-w-[60%]">
        <Skeleton className="h-10 w-56 rounded-2xl" />
      </div>
      <div className="self-start flex flex-col gap-1 max-w-[60%]">
        <Skeleton className="h-3 w-16" />
        <Skeleton className="h-10 w-40 rounded-2xl" />
      </div>
    </div>
  )
}

export default function DesignChat({
  designRequestId,
  currentUserType,
  currentUserId,
  currentUserName,
}: DesignChatProps) {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [loading, setLoading] = useState(true)
  const scrollRef = useRef<HTMLDivElement>(null)
  const bottomRef = useRef<HTMLDivElement>(null)
  const supabase = createClient()

  // Scroll to bottom
  const scrollToBottom = useCallback(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" })
  }, [])

  // Load existing messages
  useEffect(() => {
    async function loadMessages() {
      const { data, error } = await supabase
        .from("design_chat_messages")
        .select("*")
        .eq("design_request_id", designRequestId)
        .order("created_at", { ascending: true })

      if (error) {
        toast.error("Failed to load messages")
        console.error("Load messages error:", error)
      } else {
        setMessages((data as ChatMessage[]) ?? [])
      }
      setLoading(false)
    }

    loadMessages()
  }, [designRequestId, supabase])

  // Mark unread messages as read
  useEffect(() => {
    if (loading || messages.length === 0) return

    async function markRead() {
      await supabase
        .from("design_chat_messages")
        .update({ is_read: true, read_at: new Date().toISOString() })
        .eq("design_request_id", designRequestId)
        .neq("sender_type", currentUserType)
        .eq("is_read", false)
    }

    markRead()
  }, [loading, messages.length, designRequestId, currentUserType, supabase])

  // Subscribe to realtime
  useEffect(() => {
    const channel = supabase
      .channel(`design-chat-${designRequestId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "design_chat_messages",
          filter: `design_request_id=eq.${designRequestId}`,
        },
        (payload: { new: Record<string, unknown> }) => {
          const newMsg = payload.new as unknown as ChatMessage
          setMessages((prev) => {
            // Avoid duplicates
            if (prev.some((m) => m.id === newMsg.id)) return prev
            return [...prev, newMsg]
          })

          // Mark as read if from the other party
          if (newMsg.sender_type !== currentUserType) {
            supabase
              .from("design_chat_messages")
              .update({ is_read: true, read_at: new Date().toISOString() })
              .eq("id", newMsg.id)
              .then()
          }
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  }, [designRequestId, currentUserType, supabase])

  // Scroll to bottom when messages change
  useEffect(() => {
    scrollToBottom()
  }, [messages, scrollToBottom])

  // --- Send handlers ---

  async function handleSendText(content: string) {
    const { error } = await supabase.from("design_chat_messages").insert({
      design_request_id: designRequestId,
      sender_type: currentUserType,
      sender_id: currentUserId,
      sender_name: currentUserName,
      message_type: "text",
      content,
    })
    if (error) {
      toast.error("Failed to send message")
      console.error("Send text error:", error)
    } else {
      // Fire-and-forget chat notification
      // Use edge function for designers (client-side can't query showroom_users due to RLS)
      if (currentUserType === 'designer') {
        const { data: { session } } = await supabase.auth.getSession()
        if (session) {
          fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/send-design-notification`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${session.access_token}`,
            },
            body: JSON.stringify({
              event_type: 'chat_message',
              design_request_id: designRequestId,
              sender_type: currentUserType,
              sender_id: currentUserId,
              message_preview: content,
            }),
          }).catch(err => console.error('Notification edge function error:', err))
        }
      } else {
        sendDesignNotification({
          eventType: 'chat_message',
          designRequestId,
          senderType: currentUserType,
          senderId: currentUserId,
          messagePreview: content,
        })
      }
    }
  }

  async function uploadFile(
    file: File | Blob,
    fileName: string
  ): Promise<{ url: string; size: number } | null> {
    const path = `${designRequestId}/${Date.now()}_${fileName}`

    const { error: uploadError } = await supabase.storage
      .from("chat-attachments")
      .upload(path, file)

    if (uploadError) {
      toast.error("Failed to upload file")
      console.error("Upload error:", uploadError)
      return null
    }

    const { data: urlData } = supabase.storage
      .from("chat-attachments")
      .getPublicUrl(path)

    return {
      url: urlData.publicUrl,
      size: file instanceof File ? file.size : file.size,
    }
  }

  async function handleSendFile(file: File, type: "image" | "audio" | "file") {
    const result = await uploadFile(file, file.name)
    if (!result) return

    const { error } = await supabase.from("design_chat_messages").insert({
      design_request_id: designRequestId,
      sender_type: currentUserType,
      sender_id: currentUserId,
      sender_name: currentUserName,
      message_type: type,
      file_url: result.url,
      file_name: file.name,
      file_size_bytes: result.size,
    })
    if (error) {
      toast.error("Failed to send file")
      console.error("Send file error:", error)
    }
  }

  async function handleSendAudio(blob: Blob, duration: number) {
    const fileName = `recording_${duration}s.webm`
    const result = await uploadFile(blob, fileName)
    if (!result) return

    const { error } = await supabase.from("design_chat_messages").insert({
      design_request_id: designRequestId,
      sender_type: currentUserType,
      sender_id: currentUserId,
      sender_name: currentUserName,
      message_type: "audio",
      content: `Audio message (${duration}s)`,
      file_url: result.url,
      file_name: fileName,
      file_size_bytes: result.size,
    })
    if (error) {
      toast.error("Failed to send audio")
      console.error("Send audio error:", error)
    }
  }

  // --- Render ---

  function renderMessagesWithDateSeparators() {
    const elements: React.ReactNode[] = []
    let lastDate: Date | null = null

    for (const msg of messages) {
      const msgDate = new Date(msg.created_at)

      if (!lastDate || !isSameDay(lastDate, msgDate)) {
        elements.push(
          <div
            key={`sep-${msg.created_at}`}
            className="flex items-center justify-center py-2"
          >
            <span className="rounded-full bg-muted px-3 py-1 text-xs text-muted-foreground">
              {formatDateSeparator(msg.created_at)}
            </span>
          </div>
        )
        lastDate = msgDate
      }

      elements.push(
        <ChatMessageBubble
          key={msg.id}
          message={msg}
          isOwnMessage={msg.sender_type === currentUserType}
        />
      )
    }

    return elements
  }

  return (
    <div className="flex flex-col h-full border rounded-lg overflow-hidden bg-background">
      {/* Messages area */}
      <div
        ref={scrollRef}
        className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2"
      >
        {loading ? (
          <MessagesSkeleton />
        ) : messages.length === 0 ? (
          <div className="flex-1 flex flex-col items-center justify-center text-muted-foreground gap-3">
            <MessageSquareIcon className="size-10 opacity-40" />
            <p className="text-sm">No messages yet. Start the conversation!</p>
          </div>
        ) : (
          renderMessagesWithDateSeparators()
        )}
        <div ref={bottomRef} />
      </div>

      {/* Input area */}
      <ChatInput
        onSendMessage={handleSendText}
        onSendFile={handleSendFile}
        onSendAudio={handleSendAudio}
      />
    </div>
  )
}
