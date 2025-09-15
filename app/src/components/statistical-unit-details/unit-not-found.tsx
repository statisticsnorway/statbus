export default function UnitNotFound() {
  return (
    <div className="bg-gray-50 border-gray-100 border-2 p-12 text-center">
      Unit not found
      <div className="mt-2 text-gray-600 text-sm">
        This unit does not exist, or does not exist for the selected time
        period.
      </div>
    </div>
  );
}
