'use client'

import { useEffect, useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  FileIcon,
  FileImage,
  FileText,
  Download,
  Loader2,
  FolderOpen,
} from 'lucide-react'

interface DesignFile {
  id: string
  file_url: string
  file_name: string
  file_type: string | null
  file_size_bytes: number | null
  description: string | null
  version: number
  created_at: string
}

interface DesignFilesSectionProps {
  designRequestId: string
}

function formatFileSize(bytes: number | null): string {
  if (!bytes) return ''
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function getFileIcon(fileType: string | null, fileName: string) {
  const ext = fileName.split('.').pop()?.toLowerCase() || ''
  const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp']
  const isImage = imageExts.includes(ext) || fileType?.startsWith('image/')

  if (isImage) return FileImage
  if (ext === 'pdf' || fileType === 'application/pdf') return FileText
  return FileIcon
}

function isImageFile(fileType: string | null, fileName: string): boolean {
  const ext = fileName.split('.').pop()?.toLowerCase() || ''
  const imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']
  return imageExts.includes(ext) || (fileType?.startsWith('image/') ?? false)
}

export function DesignFilesSection({ designRequestId }: DesignFilesSectionProps) {
  const [files, setFiles] = useState<DesignFile[]>([])
  const [loading, setLoading] = useState(true)
  const [downloadingId, setDownloadingId] = useState<string | null>(null)
  const [thumbnailUrls, setThumbnailUrls] = useState<Record<string, string>>({})

  useEffect(() => {
    async function loadFiles() {
      const supabase = createClient()
      const { data, error } = await supabase
        .from('design_files')
        .select('*')
        .eq('design_request_id', designRequestId)
        .order('version', { ascending: false })
        .order('created_at', { ascending: false })

      if (error) {
        console.error('Error loading design files:', error)
      } else {
        setFiles(data || [])
      }
      setLoading(false)
    }

    loadFiles()
  }, [designRequestId])

  // Load signed thumbnail URLs for image files
  useEffect(() => {
    if (files.length === 0) return
    const imageFiles = files.filter((f) => isImageFile(f.file_type, f.file_name))
    if (imageFiles.length === 0) return

    async function loadThumbnails() {
      const supabase = createClient()
      const urls: Record<string, string> = {}
      for (const f of imageFiles) {
        const match = f.file_url.match(/\/storage\/v1\/object\/(?:public|sign)\/designs\/(.+)/)
        const path = match ? match[1] : f.file_url
        const { data } = await supabase.storage.from('designs').createSignedUrl(path, 3600)
        if (data?.signedUrl) urls[f.id] = data.signedUrl
      }
      setThumbnailUrls(urls)
    }
    loadThumbnails()
  }, [files])

  const handleDownload = async (file: DesignFile) => {
    setDownloadingId(file.id)
    try {
      const supabase = createClient()

      // Extract the storage path from the file_url
      // file_url may be a full URL or a storage path
      let storagePath = file.file_url
      const bucketMatch = file.file_url.match(/\/storage\/v1\/object\/(?:public|sign)\/designs\/(.+)/)
      if (bucketMatch) {
        storagePath = bucketMatch[1]
      }

      const { data, error } = await supabase.storage
        .from('designs')
        .createSignedUrl(storagePath, 300) // 5 min expiry

      if (error || !data?.signedUrl) {
        // Fallback: try opening the file_url directly
        window.open(file.file_url, '_blank')
        return
      }

      window.open(data.signedUrl, '_blank')
    } catch (err) {
      console.error('Error downloading file:', err)
      // Fallback
      window.open(file.file_url, '_blank')
    } finally {
      setDownloadingId(null)
    }
  }

  if (loading) {
    return (
      <Card>
        <CardContent className="p-4 flex items-center justify-center">
          <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
        </CardContent>
      </Card>
    )
  }

  if (files.length === 0) {
    return (
      <Card>
        <CardContent className="p-4 text-center">
          <FolderOpen className="h-8 w-8 text-gray-300 mx-auto mb-2" />
          <p className="text-sm text-gray-500">No design files uploaded yet</p>
        </CardContent>
      </Card>
    )
  }

  // Group files by version
  const grouped = files.reduce<Record<number, DesignFile[]>>((acc, file) => {
    const v = file.version || 1
    if (!acc[v]) acc[v] = []
    acc[v].push(file)
    return acc
  }, {})

  const versions = Object.keys(grouped)
    .map(Number)
    .sort((a, b) => b - a)

  return (
    <Card>
      <CardContent className="p-4 space-y-3">
        <div className="flex items-center gap-2">
          <FolderOpen className="h-4 w-4 text-gray-500" />
          <h3 className="font-semibold text-sm">Design Files</h3>
          <Badge variant="secondary" className="text-xs ml-auto">
            {files.length} file{files.length !== 1 ? 's' : ''}
          </Badge>
        </div>

        {versions.map((version) => (
          <div key={version} className="space-y-2">
            {versions.length > 1 && (
              <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">
                Version {version}
              </p>
            )}
            {grouped[version].map((file) => {
              const IconComponent = getFileIcon(file.file_type, file.file_name)
              const isImage = isImageFile(file.file_type, file.file_name)

              return (
                <div
                  key={file.id}
                  className="flex items-start gap-3 p-2 rounded-lg hover:bg-gray-50 transition-colors"
                >
                  {isImage && thumbnailUrls[file.id] ? (
                    <img
                      src={thumbnailUrls[file.id]}
                      alt={file.file_name}
                      className="w-10 h-10 rounded object-cover flex-shrink-0"
                    />
                  ) : (
                    <div className="w-10 h-10 rounded bg-gray-100 flex items-center justify-center flex-shrink-0">
                      <IconComponent className="h-5 w-5 text-gray-400" />
                    </div>
                  )}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{file.file_name}</p>
                    {file.file_size_bytes && (
                      <p className="text-xs text-gray-500">{formatFileSize(file.file_size_bytes)}</p>
                    )}
                  </div>
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleDownload(file)}
                    disabled={downloadingId === file.id}
                    className="flex-shrink-0"
                  >
                    {downloadingId === file.id ? (
                      <Loader2 className="h-4 w-4 animate-spin" />
                    ) : (
                      <Download className="h-4 w-4" />
                    )}
                  </Button>
                </div>
              )
            })}
          </div>
        ))}
      </CardContent>
    </Card>
  )
}
