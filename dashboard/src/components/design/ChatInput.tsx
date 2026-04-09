"use client"

import { useState, useRef, useCallback, type KeyboardEvent, type ChangeEvent } from "react"
import { SendIcon, PaperclipIcon, ImageIcon, XIcon } from "lucide-react"
import { cn } from "@/lib/utils"
import { Button } from "@/components/ui/button"
import { AudioRecorder } from "./AudioRecorder"

interface ChatInputProps {
  onSendMessage: (content: string) => void
  onSendFile: (file: File, type: "image" | "audio" | "file") => void
  onSendAudio: (blob: Blob, duration: number) => void
  disabled?: boolean
}

function isImageFile(file: File): boolean {
  return file.type.startsWith("image/")
}

export function ChatInput({
  onSendMessage,
  onSendFile,
  onSendAudio,
  disabled,
}: ChatInputProps) {
  const [text, setText] = useState("")
  const [pendingFile, setPendingFile] = useState<File | null>(null)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const fileInputRef = useRef<HTMLInputElement>(null)
  const imageInputRef = useRef<HTMLInputElement>(null)

  const resetTextarea = useCallback(() => {
    setText("")
    if (textareaRef.current) {
      textareaRef.current.style.height = "auto"
    }
  }, [])

  function handleSend() {
    if (pendingFile) {
      const type = isImageFile(pendingFile) ? "image" : "file"
      onSendFile(pendingFile, type)
      clearPending()
      return
    }
    const trimmed = text.trim()
    if (!trimmed) return
    onSendMessage(trimmed)
    resetTextarea()
  }

  function handleKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault()
      handleSend()
    }
  }

  function handleTextChange(e: ChangeEvent<HTMLTextAreaElement>) {
    setText(e.target.value)
    // Auto-expand up to 3 lines (~72px)
    const el = e.target
    el.style.height = "auto"
    el.style.height = Math.min(el.scrollHeight, 72) + "px"
  }

  function handleFileSelected(file: File) {
    setPendingFile(file)
    if (isImageFile(file)) {
      const url = URL.createObjectURL(file)
      setPreviewUrl(url)
    } else {
      setPreviewUrl(null)
    }
  }

  function clearPending() {
    if (previewUrl) URL.revokeObjectURL(previewUrl)
    setPendingFile(null)
    setPreviewUrl(null)
    if (fileInputRef.current) fileInputRef.current.value = ""
    if (imageInputRef.current) imageInputRef.current.value = ""
  }

  function handleRecordingComplete(blob: Blob, duration: number) {
    onSendAudio(blob, duration)
  }

  const hasContent = text.trim().length > 0 || pendingFile !== null

  return (
    <div className="border-t bg-background p-3">
      {/* Pending file preview */}
      {pendingFile && (
        <div className="mb-2 flex items-center gap-2 rounded-lg border bg-muted/50 p-2">
          {previewUrl ? (
            <img
              src={previewUrl}
              alt="Preview"
              className="size-12 rounded object-cover"
            />
          ) : (
            <div className="flex size-12 items-center justify-center rounded bg-muted">
              <PaperclipIcon className="size-5 text-muted-foreground" />
            </div>
          )}
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium truncate">{pendingFile.name}</p>
            <p className="text-xs text-muted-foreground">
              {(pendingFile.size / 1024).toFixed(1)} KB
            </p>
          </div>
          <Button
            variant="ghost"
            size="icon-sm"
            onClick={clearPending}
            className="shrink-0"
          >
            <XIcon className="size-4" />
          </Button>
        </div>
      )}

      <div className="flex items-end gap-1.5">
        {/* Hidden file inputs */}
        <input
          ref={fileInputRef}
          type="file"
          className="hidden"
          onChange={(e) => {
            const f = e.target.files?.[0]
            if (f) handleFileSelected(f)
          }}
        />
        <input
          ref={imageInputRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => {
            const f = e.target.files?.[0]
            if (f) handleFileSelected(f)
          }}
        />

        {/* Attachment button */}
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={() => fileInputRef.current?.click()}
          disabled={disabled}
          title="Attach file"
        >
          <PaperclipIcon className="size-4" />
        </Button>

        {/* Image button */}
        <Button
          variant="ghost"
          size="icon-sm"
          onClick={() => imageInputRef.current?.click()}
          disabled={disabled}
          title="Attach image"
        >
          <ImageIcon className="size-4" />
        </Button>

        {/* Audio recorder */}
        <AudioRecorder
          onRecordingComplete={handleRecordingComplete}
          disabled={disabled}
        />

        {/* Text area */}
        <textarea
          ref={textareaRef}
          value={text}
          onChange={handleTextChange}
          onKeyDown={handleKeyDown}
          placeholder="Type a message..."
          disabled={disabled}
          rows={1}
          className={cn(
            "flex-1 resize-none rounded-lg border bg-background px-3 py-2 text-sm",
            "placeholder:text-muted-foreground",
            "focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring",
            "disabled:cursor-not-allowed disabled:opacity-50",
            "max-h-[72px] min-h-[36px]"
          )}
        />

        {/* Send button */}
        <Button
          size="icon-sm"
          onClick={handleSend}
          disabled={disabled || !hasContent}
          title="Send message"
        >
          <SendIcon className="size-4" />
        </Button>
      </div>
    </div>
  )
}
