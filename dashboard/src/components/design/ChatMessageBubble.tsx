"use client"

import { useState } from "react"
import { format, isToday, isYesterday } from "date-fns"
import {
  FileIcon,
  DownloadIcon,
  PlayIcon,
  PauseIcon,
} from "lucide-react"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
} from "@/components/ui/dialog"

interface ChatMessageBubbleProps {
  message: {
    id: string
    sender_type: "designer" | "showroom"
    sender_name: string
    message_type: "text" | "image" | "audio" | "file"
    content: string | null
    file_url: string | null
    file_name: string | null
    file_size_bytes: number | null
    created_at: string
  }
  isOwnMessage: boolean
}

function formatTimestamp(dateStr: string): string {
  const date = new Date(dateStr)
  const timeStr = format(date, "h:mm a")
  if (isToday(date)) return timeStr
  if (isYesterday(date)) return `Yesterday ${timeStr}`
  return `${format(date, "MMM d")} ${timeStr}`
}

function formatFileSize(bytes: number | null): string {
  if (!bytes) return ""
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function AudioPlayer({ src }: { src: string }) {
  const [isPlaying, setIsPlaying] = useState(false)
  const [progress, setProgress] = useState(0)
  const [duration, setDuration] = useState(0)
  const [audioEl, setAudioEl] = useState<HTMLAudioElement | null>(null)

  function handleRef(el: HTMLAudioElement | null) {
    if (el && el !== audioEl) {
      setAudioEl(el)
      el.addEventListener("loadedmetadata", () => setDuration(el.duration))
      el.addEventListener("timeupdate", () => {
        if (el.duration) setProgress((el.currentTime / el.duration) * 100)
      })
      el.addEventListener("ended", () => {
        setIsPlaying(false)
        setProgress(0)
      })
    }
  }

  function togglePlay() {
    if (!audioEl) return
    if (isPlaying) {
      audioEl.pause()
    } else {
      audioEl.play()
    }
    setIsPlaying(!isPlaying)
  }

  function handleProgressClick(e: React.MouseEvent<HTMLDivElement>) {
    if (!audioEl || !duration) return
    const rect = e.currentTarget.getBoundingClientRect()
    const pct = (e.clientX - rect.left) / rect.width
    audioEl.currentTime = pct * duration
    setProgress(pct * 100)
  }

  function formatTime(seconds: number): string {
    const m = Math.floor(seconds / 60)
    const s = Math.floor(seconds % 60)
    return `${m}:${s.toString().padStart(2, "0")}`
  }

  return (
    <div className="flex items-center gap-2 min-w-[200px]">
      <audio ref={handleRef} src={src} preload="metadata" />
      <Button
        variant="ghost"
        size="icon-sm"
        onClick={togglePlay}
        className="shrink-0"
      >
        {isPlaying ? (
          <PauseIcon className="size-4" />
        ) : (
          <PlayIcon className="size-4" />
        )}
      </Button>
      <div className="flex-1 flex flex-col gap-1">
        <div
          className="h-1.5 rounded-full bg-background/30 cursor-pointer relative overflow-hidden"
          onClick={handleProgressClick}
        >
          <div
            className="absolute inset-y-0 left-0 rounded-full bg-current opacity-70 transition-all"
            style={{ width: `${progress}%` }}
          />
        </div>
        <span className="text-[10px] opacity-70">
          {duration ? formatTime(audioEl?.currentTime ?? 0) + " / " + formatTime(duration) : "0:00"}
        </span>
      </div>
    </div>
  )
}

export function ChatMessageBubble({ message, isOwnMessage }: ChatMessageBubbleProps) {
  const [lightboxOpen, setLightboxOpen] = useState(false)

  return (
    <div
      className={cn(
        "flex flex-col max-w-[75%] animate-in fade-in slide-in-from-bottom-1 duration-200",
        isOwnMessage ? "self-end items-end" : "self-start items-start"
      )}
    >
      {!isOwnMessage && (
        <span className="text-xs text-muted-foreground mb-1 px-1">
          {message.sender_type === 'designer' ? 'Designer' : 'Showroom'}
        </span>
      )}

      <div
        className={cn(
          "rounded-2xl px-4 py-2.5 break-words",
          isOwnMessage
            ? "bg-primary text-primary-foreground rounded-br-md"
            : "bg-muted text-foreground rounded-bl-md"
        )}
      >
        {message.message_type === "text" && (
          <p className="text-sm whitespace-pre-wrap">{message.content}</p>
        )}

        {message.message_type === "image" && message.file_url && (
          <>
            <button
              onClick={() => setLightboxOpen(true)}
              className="block cursor-pointer"
            >
              <img
                src={message.file_url}
                alt={message.file_name ?? "Image"}
                className="rounded-lg max-w-[280px] max-h-[200px] object-cover"
                loading="lazy"
              />
            </button>
            <Dialog open={lightboxOpen} onOpenChange={setLightboxOpen}>
              <DialogContent className="max-w-[90vw] max-h-[90vh] p-2 sm:max-w-[80vw]">
                <img
                  src={message.file_url}
                  alt={message.file_name ?? "Image"}
                  className="w-full h-full object-contain max-h-[85vh] rounded"
                />
              </DialogContent>
            </Dialog>
          </>
        )}

        {message.message_type === "audio" && message.file_url && (
          <AudioPlayer src={message.file_url} />
        )}

        {message.message_type === "file" && (
          <a
            href={message.file_url ?? "#"}
            target="_blank"
            rel="noopener noreferrer"
            download={message.file_name ?? undefined}
            className={cn(
              "flex items-center gap-3 no-underline",
              isOwnMessage ? "text-primary-foreground" : "text-foreground"
            )}
          >
            <FileIcon className="size-8 shrink-0 opacity-70" />
            <div className="flex flex-col min-w-0">
              <span className="text-sm font-medium truncate">
                {message.file_name ?? "File"}
              </span>
              {message.file_size_bytes && (
                <span className="text-xs opacity-70">
                  {formatFileSize(message.file_size_bytes)}
                </span>
              )}
            </div>
            <DownloadIcon className="size-4 shrink-0 opacity-70 ml-2" />
          </a>
        )}
      </div>

      <span className="text-[10px] text-muted-foreground mt-1 px-1">
        {formatTimestamp(message.created_at)}
      </span>
    </div>
  )
}
