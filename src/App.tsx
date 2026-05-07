import { BrowserRouter, Route, Routes } from 'react-router-dom'
import AppShell from './components/AppShell'
import CalcPage from './pages/CalcPage'
import HomePage from './pages/HomePage'

export default function App() {
  return (
    <BrowserRouter>
      <AppShell>
        <Routes>
          <Route path="/" element={<HomePage />} />
          <Route path="/calc" element={<CalcPage />} />
        </Routes>
      </AppShell>
    </BrowserRouter>
  )
}
