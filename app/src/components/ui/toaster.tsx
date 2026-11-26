"use client"

import { useToast } from "@/hooks/use-toast"
import {
  Toast,
  ToastClose,
  ToastDescription,
  ToastProvider,
  ToastTitle,
  ToastViewport,
} from "@/components/ui/toast"

/**
 * How long a notification stays before it closes by itself: long enough to read it (and to take a
 * screenshot), and it stays while the pointer is over it. Owner 2026-11-26: the default 5 s was gone
 * before he could read it.
 */
const TOAST_DURATION_MS = 10_000

export function Toaster() {
  const { toasts } = useToast()

  return (
    <ToastProvider duration={TOAST_DURATION_MS}>
      {toasts.map(function ({ id, title, description, action, ...props }) {
        return (
          <Toast key={id} {...props}>
            <div className="grid gap-1">
              {title && <ToastTitle>{title}</ToastTitle>}
              {description && (
                <ToastDescription>{description}</ToastDescription>
              )}
            </div>
            {action}
            <ToastClose />
          </Toast>
        )
      })}
      <ToastViewport />
    </ToastProvider>
  )
}
