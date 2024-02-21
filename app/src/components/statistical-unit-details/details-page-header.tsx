export const DetailsPageHeader = ({name}: { name?: string | null }) => (
  <div className="space-y-0.5 bg-gray-50 border-b-2 border-gray-100 p-4">
    <h2 className="text-2xl font-semibold tracking-tight">
      {name || "Unnamed Organization"}
    </h2>
    <p className="text-sm">
      Manage settings for {name || "Unnamed Organization"}
    </p>
  </div>
)
