"use client";
import Link from "next/link";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

import {
  BarChart3,
  ChevronRight,
  Database,
  Hash,
  Power,
  Proportions,
  ScrollText,
  Users,
} from "lucide-react";

export default function AdminPage() {
  const adminSections = [
    {
      title: "Users",
      description: "Manage and create users",
      href: "/admin/users",
      icon: Users,
    },
    {
      title: "External Identifiers",
      description: "View, create and manage external identifier types",
      href: "/admin/external-idents",
      icon: Hash,
    },
    {
      title: "Statistical Variables",
      description: "View, create and manage statistical variables",
      href: "/admin/statistical-variables",
      icon: BarChart3,
    },
    {
      title: "Unit Sizes",
      description: "View, create and manage unit sizes",
      href: "/admin/unit-size",
      icon: Proportions,
    },
    {
      title: "Data Sources",
      description: "View, create and manage data source codes",
      href: "/admin/data-sources",
      icon: Database,
    },
    {
      title: "Statuses",
      description: "View, create and manage status codes",
      href: "/admin/status",
      icon: Power,
    },
    {
      title: "Activity Category Settings",
      description: "Configure activity category standards",
      href: "/admin/activity-category-settings",
      icon: ScrollText,
    },
  ];

  return (
    <main className="mx-auto flex w-full max-w-4xl flex-col px-2 py-8 md:py-12">
      <div className="space-y-4">
        <div>
          <h1 className="text-2xl mb-3">Admin</h1>
          <p>Manage users and customize Statbus</p>
        </div>
        
          <div className="flex flex-col gap-4">
            <div className="grid gap-6 auto-rows-fr md:grid-cols-3">
              {adminSections.map((section) => {
                const Icon = section.icon;
                return (
                  <Link
                    key={section.href}
                    href={section.href}
                    
                  >
                    <Card className="h-full overflow-hidden hover:border-gray-400">
                      <CardHeader className="flex flex-row items-center justify-between space-y-0 bg-gray-100 border-b px-3 py-2">
                        <CardTitle className="text-sm font-normal flex gap-2 items-center">
                          <Icon className="h-4 w-4" />
                          {section.title}
                        </CardTitle>
                        <ChevronRight className="w-4 h-4" />
                      </CardHeader>
                      <CardContent className="px-4 py-3 text-sm">
                        {section.description}
                      </CardContent>
                    </Card>
                  </Link>
                );
              })}
            </div>
          </div>
     
      </div>
    </main>
  );
}
