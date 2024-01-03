import type {Metadata} from 'next'
import {Inter} from 'next/font/google'
import './globals.css'
import React from "react";
import NavBar from "@/components/NavBar";
import {cn} from "@/lib/utils";

const inter = Inter({subsets: ['latin']})

export const metadata: Metadata = {
  title: 'Statbus',
  description: 'Simple To Use, Simple To Understand, Simply useful!',
}

export default function RootLayout({children}: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full bg-white">
      <body className={cn("min-h-screen bg-background font-sans antialiased", inter.className)}>
        <NavBar/>
        {children}
      </body>
    </html>
  )
}
