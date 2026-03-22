import * as React from "react"

import { cn } from "@/lib/utils"

const Textarea = React.forwardRef<
  HTMLTextAreaElement,
  React.ComponentProps<"textarea">
>(({ className, ...props }, ref) => {
  return (
    <textarea
      className={cn(
        "flex min-h-[80px] w-full rounded-md border border-oklch(0.92 0.004 286.32) bg-oklch(1 0 0) px-3 py-2 text-base ring-offset-oklch(1 0 0) placeholder:text-oklch(0.552 0.016 285.938) focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-oklch(0.705 0.015 286.067) focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50 md:text-sm dark:border-oklch(1 0 0 / 10%) dark:border-oklch(1 0 0 / 15%) dark:bg-oklch(0.141 0.005 285.823) dark:ring-offset-oklch(0.141 0.005 285.823) dark:placeholder:text-oklch(0.705 0.015 286.067) dark:focus-visible:ring-oklch(0.552 0.016 285.938)",
        className
      )}
      ref={ref}
      {...props}
    />
  )
})
Textarea.displayName = "Textarea"

export { Textarea }
