import type {Metadata} from 'next'
import {Inter} from 'next/font/google'
import './globals.css'
import React from "react";
import Navbar from "@/components/navbar";
import {cn} from "@/lib/utils";
import {CommandPalette} from "@/components/command-palette/command-palette";
import {Toaster} from "@/components/ui/toaster";
import Footer from "@/components/footer";

const inter = Inter({subsets: ['latin']})

export const metadata: Metadata = {
    title: 'StatBus',
    description: 'Simple To Use, Simple To Understand, Simply useful!',
}

export default function RootLayout({children}: { readonly children: React.ReactNode }) {
    return (
        <html lang="en" className="h-full bg-white">
        <body className={cn("grid grid-rows-[auto_1fr_auto] h-full font-sans antialiased", inter.className)}>
        <Navbar/>
        {children}
        <CommandPalette/>
        <Toaster/>
        <Footer/>
        </body>
        </html>
    )
}
