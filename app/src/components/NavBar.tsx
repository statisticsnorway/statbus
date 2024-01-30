import ProfileAvatar from "@/components/ProfileAvatar";

export default function NavBar() {
  return (
    <nav className="bg-gray-100">
      <div className="max-w-screen-xl flex flex-wrap items-center justify-between mx-auto p-4">
        <a href="/" className="flex items-center space-x-3 rtl:space-x-reverse">
          <img src="https://demo.statbus.org/logo.png" className="h-8" alt="Statbus Logo"/>
          <span className="self-center text-2xl font-semibold whitespace-nowrap dark:text-white">Statbus</span>
        </a>
        <div className="items-center justify-between flex w-auto order-1" id="navbar-user">
          <ul className="flex flex-col font-medium">
            <li>
              <ProfileAvatar/>
            </li>
          </ul>
        </div>
      </div>
    </nav>
  )
}
