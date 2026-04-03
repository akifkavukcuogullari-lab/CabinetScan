'use client'

import { useState, useEffect, useRef, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { toast } from 'sonner'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import {
  Upload,
  FileIcon,
  FileImage,
  FileText,
  Download,
  Loader2,
  FolderOpen,
  Trash2,
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

interface DesignFileUploadProps {
  designRequestId: string
  designerId: string
  currentStatus: string
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

export function DesignFileUpload({
  designRequestId,
  designerId,
  currentStatus,
}: DesignFileUploadProps) {
  const router = useRouter()
  const [files, setFiles] = useState<DesignFile[]>([])
  const [loading, setLoading] = useState(true)
  const [uploading, setUploading] = useState(false)
  const [downloadingId, setDownloadingId] = useState<string | null>(null)
  const [isDragOver, setIsDragOver] = useState(false)
  const [thumbnailUrls, setThumbnailUrls] = useState<Record<string, string>>({})
  const fileInputRef = useRef<HTMLInputElement>(null)

  const canUpload = currentStatus === 'in_progress' || currentStatus === 'revision_requested'

  const loadFiles = useCallback(async () => {
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
  }, [designRequestId])

  useEffect(() => {
    loadFiles()
  }, [loadFiles])

  // Load signed thumbnail URLs for image files
  useEffect(() => {
    if (files.length === 0) return
    const imageFiles = files.filter((f) => isImageFile(f.file_type, f.file_name))
    if (imageFiles.length === 0) return

    async function loadThumbnails() {
      const supabase = createClient()
      const urls: Record<string, string> = {}
      for (const f of imageFiles) {
        const storagePath = f.file_url.match(/\/storage\/v1\/object\/(?:public|sign)\/designs\/(.+)/)
        const path = storagePath ? storagePath[1] : f.file_url
        const { data } = await supabase.storage.from('designs').createSignedUrl(path, 3600)
        if (data?.signedUrl) urls[f.id] = data.signedUrl
      }
      setThumbnailUrls(urls)
    }
    loadThumbnails()
  }, [files])

  const getNextVersion = (): number => {
    if (files.length === 0) return 1
    return Math.max(...files.map((f) => f.version || 1)) + 1
  }

  const uploadFiles = async (fileList: FileList | File[]) => {
    if (!canUpload) return

    setUploading(true)
    const supabase = createClient()
    const version = getNextVersion()

    try {
      for (const file of Array.from(fileList)) {
        const sanitizedName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
        const storagePath = `${designRequestId}/${version}_${sanitizedName}`

        const { error: uploadError } = await supabase.storage
          .from('designs')
          .upload(storagePath, file, {
            upsert: false,
          })

        if (uploadError) {
          console.error('Upload error:', uploadError)
          toast.error(`Failed to upload ${file.name}`)
          continue
        }

        // Store the storage path (not public URL, since bucket is private)
        const { error: insertError } = await supabase
          .from('design_files')
          .insert({
            design_request_id: designRequestId,
            designer_id: designerId,
            file_url: storagePath,
            file_name: file.name,
            file_type: file.type || null,
            file_size_bytes: file.size,
            version,
          })

        if (insertError) {
          console.error('Insert error:', insertError)
          toast.error(`Failed to save record for ${file.name}`)
          continue
        }

        toast.success(`Uploaded ${file.name}`)
      }

      await loadFiles()
      router.refresh()
    } catch (err) {
      console.error('Error during upload:', err)
      toast.error('An unexpected error occurred during upload.')
    } finally {
      setUploading(false)
      if (fileInputRef.current) {
        fileInputRef.current.value = ''
      }
    }
  }

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      uploadFiles(e.target.files)
    }
  }

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDragOver(true)
  }

  const handleDragLeave = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDragOver(false)
  }

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault()
    setIsDragOver(false)
    if (e.dataTransfer.files && e.dataTransfer.files.length > 0 && canUpload) {
      uploadFiles(e.dataTransfer.files)
    }
  }

  const getStoragePath = (fileUrl: string): string => {
    // Handle both old public URLs and new storage paths
    const bucketMatch = fileUrl.match(/\/storage\/v1\/object\/(?:public|sign)\/designs\/(.+)/)
    return bucketMatch ? bucketMatch[1] : fileUrl
  }

  const getSignedUrl = async (fileUrl: string): Promise<string | null> => {
    const supabase = createClient()
    const storagePath = getStoragePath(fileUrl)
    const { data, error } = await supabase.storage
      .from('designs')
      .createSignedUrl(storagePath, 300)
    if (error || !data?.signedUrl) return null
    return data.signedUrl
  }

  const handleDownload = async (file: DesignFile) => {
    setDownloadingId(file.id)
    try {
      const url = await getSignedUrl(file.file_url)
      window.open(url || file.file_url, '_blank')
    } catch {
      window.open(file.file_url, '_blank')
    } finally {
      setDownloadingId(null)
    }
  }

  const handleDelete = async (file: DesignFile) => {
    if (!canUpload) return

    const supabase = createClient()
    const storagePath = getStoragePath(file.file_url)
    await supabase.storage.from('designs').remove([storagePath])

    // Delete from database
    const { error } = await supabase
      .from('design_files')
      .delete()
      .eq('id', file.id)

    if (error) {
      console.error('Error deleting file:', error)
      toast.error('Failed to delete file.')
      return
    }

    toast.success('File deleted.')
    await loadFiles()
    router.refresh()
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
          {files.length > 0 && (
            <Badge variant="secondary" className="text-xs ml-auto">
              {files.length} file{files.length !== 1 ? 's' : ''}
            </Badge>
          )}
        </div>

        {/* Upload area */}
        {canUpload && (
          <div
            className={`
              relative border-2 border-dashed rounded-lg p-4 text-center transition-colors cursor-pointer
              ${isDragOver ? 'border-blue-400 bg-blue-50' : 'border-gray-200 hover:border-gray-300'}
              ${uploading ? 'opacity-50 pointer-events-none' : ''}
            `}
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onDrop={handleDrop}
            onClick={() => fileInputRef.current?.click()}
          >
            <input
              ref={fileInputRef}
              type="file"
              multiple
              className="hidden"
              onChange={handleFileChange}
              accept=".pdf,.png,.jpg,.jpeg,.dwg,.dxf,.ai,.psd,.zip,.rar"
            />
            {uploading ? (
              <div className="flex flex-col items-center gap-2">
                <Loader2 className="h-6 w-6 animate-spin text-blue-500" />
                <p className="text-sm text-gray-500">Uploading...</p>
              </div>
            ) : (
              <div className="flex flex-col items-center gap-2">
                <Upload className="h-6 w-6 text-gray-400" />
                <p className="text-sm text-gray-500">
                  Drop files here or click to browse
                </p>
                <p className="text-xs text-gray-400">
                  PDF, images, DWG, DXF, AI, PSD, ZIP
                </p>
              </div>
            )}
          </div>
        )}

        {/* File list */}
        {loading ? (
          <div className="flex items-center justify-center py-4">
            <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
          </div>
        ) : files.length === 0 ? (
          <div className="text-center py-3">
            <p className="text-sm text-gray-500">No files uploaded yet</p>
          </div>
        ) : (
          <div className="space-y-3">
            {versions.map((version) => (
              <div key={version} className="space-y-1.5">
                <p className="text-xs font-medium text-gray-500 uppercase tracking-wide">
                  Version {version}
                </p>
                {grouped[version].map((file) => {
                  const IconComponent = getFileIcon(file.file_type, file.file_name)
                  const isImage = isImageFile(file.file_type, file.file_name)

                  return (
                    <div
                      key={file.id}
                      className="flex items-center gap-2.5 p-2 rounded-lg hover:bg-gray-50 transition-colors group"
                    >
                      {isImage && thumbnailUrls[file.id] ? (
                        <img
                          src={thumbnailUrls[file.id]}
                          alt={file.file_name}
                          className="w-9 h-9 rounded object-cover flex-shrink-0"
                        />
                      ) : (
                        <div className="w-9 h-9 rounded bg-gray-100 flex items-center justify-center flex-shrink-0">
                          <IconComponent className="h-4 w-4 text-gray-400" />
                        </div>
                      )}
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium truncate">{file.file_name}</p>
                        {file.file_size_bytes && (
                          <p className="text-xs text-gray-500">{formatFileSize(file.file_size_bytes)}</p>
                        )}
                      </div>
                      <div className="flex items-center gap-1 flex-shrink-0">
                        <Button
                          variant="ghost"
                          size="icon"
                          className="h-7 w-7"
                          onClick={() => handleDownload(file)}
                          disabled={downloadingId === file.id}
                        >
                          {downloadingId === file.id ? (
                            <Loader2 className="h-3.5 w-3.5 animate-spin" />
                          ) : (
                            <Download className="h-3.5 w-3.5" />
                          )}
                        </Button>
                        {canUpload && (
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 text-gray-400 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity"
                            onClick={() => handleDelete(file)}
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </Button>
                        )}
                      </div>
                    </div>
                  )
                })}
              </div>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  )
}
