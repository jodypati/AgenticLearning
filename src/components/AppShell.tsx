import type { ReactNode } from 'react'
import { Link, NavLink } from 'react-router-dom'
import './AppShell.css'

type AppShellProps = {
  children: ReactNode
}

export default function AppShell({ children }: AppShellProps) {
  return (
    <>
      <header className="app-shell">
        <Link to="/" className="app-shell__brand">
          Apotek POS
        </Link>
        <nav className="app-shell__nav" aria-label="Navigasi utama">
          <NavLink
            to="/"
            end
            className={({ isActive }) =>
              'app-shell__link' + (isActive ? ' app-shell__link--active' : '')
            }
          >
            Beranda
          </NavLink>
        </nav>
      </header>
      {children}
    </>
  )
}
