import ProfileAvatar from "@/components/profile-avatar";
import Image from "next/image";
import logo from '@/../public/statbus-logo.png'

export default function Navbar() {
  return (
    <nav className="bg-gray-100">
      <div className="max-w-screen-xl flex flex-wrap items-center justify-between mx-auto p-4">
        <a href="/" className="flex items-center space-x-3 rtl:space-x-reverse">
          <Image src={logo} alt="Statbus Logo" width={32} height={32} className="h-8" />
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
