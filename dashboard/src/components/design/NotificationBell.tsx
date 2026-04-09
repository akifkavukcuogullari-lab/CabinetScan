'use client'

import { useEffect, useState, useCallback, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover'
import { cn } from '@/lib/utils'
import { formatDistanceToNow } from 'date-fns'
import {
  Bell,
  UserCheck,
  Truck,
  CheckCircle2,
  RotateCcw,
  XCircle,
  Trophy,
  Ban,
  MessageCircle,
  Clock,
  CheckCheck,
  Inbox,
} from 'lucide-react'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type EventType =
  | 'design_accepted'
  | 'design_delivered'
  | 'design_approved'
  | 'design_revision'
  | 'design_dropped'
  | 'design_completed'
  | 'design_canceled'
  | 'chat_message'
  | 'estimate_set'

interface DesignNotification {
  id: string
  recipient_type: 'designer' | 'showroom'
  recipient_id: string
  event_type: EventType
  design_request_id: string | null
  project_reference: string | null
  message: string
  is_read: boolean
  read_at: string | null
  email_sent: boolean
  created_at: string
}

interface NotificationBellProps {
  recipientType: 'designer' | 'showroom'
}

// ---------------------------------------------------------------------------
// Event type icon mapping
// ---------------------------------------------------------------------------

const EVENT_ICONS: Record<EventType, React.ComponentType<{ className?: string }>> = {
  design_accepted: UserCheck,
  design_delivered: Truck,
  design_approved: CheckCircle2,
  design_revision: RotateCcw,
  design_dropped: XCircle,
  design_completed: Trophy,
  design_canceled: Ban,
  chat_message: MessageCircle,
  estimate_set: Clock,
}

const EVENT_COLORS: Record<EventType, string> = {
  design_accepted: 'text-green-600',
  design_delivered: 'text-blue-600',
  design_approved: 'text-emerald-600',
  design_revision: 'text-amber-600',
  design_dropped: 'text-red-500',
  design_completed: 'text-purple-600',
  design_canceled: 'text-gray-500',
  chat_message: 'text-blue-500',
  estimate_set: 'text-orange-500',
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

export function NotificationBell({ recipientType }: NotificationBellProps) {
  const supabase = createClient()
  const router = useRouter()

  const [notifications, setNotifications] = useState<DesignNotification[]>([])
  const [unreadCount, setUnreadCount] = useState(0)
  const [open, setOpen] = useState(false)
  const [loading, setLoading] = useState(true)
  const [limit, setLimit] = useState(20)

  // Store recipientId once resolved
  const recipientIdRef = useRef<string | null>(null)

  // ----------------------------------
  // Resolve recipientId on mount
  // ----------------------------------
  const resolveRecipientId = useCallback(async (): Promise<string | null> => {
    if (recipientIdRef.current) return recipientIdRef.current

    const { data: { user } } = await supabase.auth.getUser()
    if (!user) return null

    if (recipientType === 'showroom') {
      recipientIdRef.current = user.id
      return user.id
    }

    // For designers, look up the designer row
    const { data: designer } = await supabase
      .from('designers')
      .select('id')
      .eq('user_id', user.id)
      .single()

    if (designer) {
      recipientIdRef.current = designer.id
      return designer.id
    }

    return null
  }, [supabase, recipientType])

  // ----------------------------------
  // Fetch notifications
  // ----------------------------------
  const fetchNotifications = useCallback(async () => {
    const recipientId = await resolveRecipientId()
    if (!recipientId) {
      setLoading(false)
      return
    }

    const { data, error } = await supabase
      .from('design_notifications')
      .select('*')
      .eq('recipient_type', recipientType)
      .eq('recipient_id', recipientId)
      .order('created_at', { ascending: false })
      .limit(limit)

    if (!error && data) {
      setNotifications(data as DesignNotification[])
      setUnreadCount(data.filter((n: DesignNotification) => !n.is_read).length)
    }

    setLoading(false)
  }, [supabase, recipientType, resolveRecipientId, limit])

  // ----------------------------------
  // Mount: fetch + subscribe to realtime
  // ----------------------------------
  useEffect(() => {
    fetchNotifications()

    let channel: ReturnType<typeof supabase.channel> | null = null

    async function subscribe() {
      const recipientId = await resolveRecipientId()
      if (!recipientId) return

      channel = supabase
        .channel(`notifications-${recipientId}`)
        .on(
          'postgres_changes',
          {
            event: 'INSERT',
            schema: 'public',
            table: 'design_notifications',
            filter: `recipient_id=eq.${recipientId}`,
          },
          (payload: { new: Record<string, unknown> }) => {
            const newNotification = payload.new as unknown as DesignNotification
            // Only add if it matches our recipientType
            if (newNotification.recipient_type === recipientType) {
              setNotifications((prev) => [newNotification, ...prev])
              if (!newNotification.is_read) {
                setUnreadCount((prev) => prev + 1)
              }
            }
          }
        )
        .subscribe()
    }

    subscribe()

    return () => {
      if (channel) {
        supabase.removeChannel(channel)
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [limit])

  // ----------------------------------
  // Mark single notification as read
  // ----------------------------------
  const markAsRead = async (notification: DesignNotification) => {
    if (!notification.is_read) {
      // Optimistically update UI
      setNotifications((prev) =>
        prev.map((n) =>
          n.id === notification.id
            ? { ...n, is_read: true, read_at: new Date().toISOString() }
            : n
        )
      )
      setUnreadCount((prev) => Math.max(0, prev - 1))

      await supabase
        .from('design_notifications')
        .update({ is_read: true, read_at: new Date().toISOString() })
        .eq('id', notification.id)
    }

    // Navigate to the relevant project
    if (notification.design_request_id) {
      setOpen(false)
      if (recipientType === 'designer') {
        router.push(`/designer/projects/${notification.design_request_id}`)
      } else {
        router.push(`/showroom/projects/${notification.project_reference || ''}`)
      }
    }
  }

  // ----------------------------------
  // Mark all as read
  // ----------------------------------
  const markAllAsRead = async () => {
    const recipientId = recipientIdRef.current
    if (!recipientId) return

    // Optimistic update
    setNotifications((prev) =>
      prev.map((n) => ({ ...n, is_read: true, read_at: new Date().toISOString() }))
    )
    setUnreadCount(0)

    await supabase
      .from('design_notifications')
      .update({ is_read: true, read_at: new Date().toISOString() })
      .eq('recipient_type', recipientType)
      .eq('recipient_id', recipientId)
      .eq('is_read', false)
  }

  // ----------------------------------
  // Show more
  // ----------------------------------
  const handleViewMore = () => {
    setLimit((prev) => prev + 20)
  }

  // ----------------------------------
  // Render
  // ----------------------------------
  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="relative h-9 w-9"
          aria-label={`Notifications${unreadCount > 0 ? ` (${unreadCount} unread)` : ''}`}
        >
          <Bell className="h-5 w-5" />
          {unreadCount > 0 && (
            <span className="absolute -top-0.5 -right-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold text-white">
              {unreadCount > 99 ? '99+' : unreadCount}
            </span>
          )}
        </Button>
      </PopoverTrigger>

      <PopoverContent
        align="end"
        sideOffset={8}
        className="w-80 p-0 sm:w-96"
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b px-4 py-3">
          <h3 className="text-sm font-semibold">Notifications</h3>
          {unreadCount > 0 && (
            <button
              onClick={markAllAsRead}
              className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
            >
              <CheckCheck className="h-3.5 w-3.5" />
              Mark all as read
            </button>
          )}
        </div>

        {/* Notification list */}
        <div className="max-h-[400px] overflow-y-auto">
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <div className="h-5 w-5 animate-spin rounded-full border-2 border-muted-foreground border-t-transparent" />
            </div>
          ) : notifications.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-10 text-muted-foreground">
              <Inbox className="h-8 w-8 mb-2 opacity-50" />
              <p className="text-sm">No notifications</p>
            </div>
          ) : (
            <>
              {notifications.map((notification) => {
                const Icon = EVENT_ICONS[notification.event_type] || Bell
                const iconColor = EVENT_COLORS[notification.event_type] || 'text-gray-500'

                return (
                  <button
                    key={notification.id}
                    onClick={() => markAsRead(notification)}
                    className={cn(
                      'flex w-full items-start gap-3 px-4 py-3 text-left transition-colors hover:bg-muted/50',
                      !notification.is_read && 'bg-blue-50/50 dark:bg-blue-950/20'
                    )}
                  >
                    {/* Icon */}
                    <div className={cn('mt-0.5 shrink-0', iconColor)}>
                      <Icon className="h-4 w-4" />
                    </div>

                    {/* Content */}
                    <div className="min-w-0 flex-1">
                      <p className="text-sm leading-snug line-clamp-2">
                        {notification.message}
                      </p>
                      <p className="mt-1 text-xs text-muted-foreground">
                        {formatDistanceToNow(new Date(notification.created_at), {
                          addSuffix: true,
                        })}
                      </p>
                    </div>

                    {/* Unread dot */}
                    {!notification.is_read && (
                      <div className="mt-2 shrink-0">
                        <span className="block h-2 w-2 rounded-full bg-blue-500" />
                      </div>
                    )}
                  </button>
                )
              })}

              {/* View more */}
              {notifications.length >= limit && (
                <div className="border-t px-4 py-2">
                  <button
                    onClick={handleViewMore}
                    className="w-full text-center text-xs text-muted-foreground hover:text-foreground transition-colors py-1"
                  >
                    View more
                  </button>
                </div>
              )}
            </>
          )}
        </div>
      </PopoverContent>
    </Popover>
  )
}
