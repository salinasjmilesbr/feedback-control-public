import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import './styles/virtus-foundation.css'
import './styles/virtus-audit.css'
import App from './App.tsx'
import { executarResetBaseDesenvolvimento } from './services/resetBaseDesenvolvimento'

executarResetBaseDesenvolvimento()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
