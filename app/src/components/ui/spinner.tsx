export function Spinner({ message }: { message?: string }) {
  return (
    <div className="flex flex-col justify-center items-center">
      <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-b-2 border-gray-900"></div>
      {message && <p className="mt-2 text-gray-700">{message}</p>}
    </div>
  );
}
