import { createRoot } from 'react-dom/client'
import { App } from './App'
import './styles.css'
import { postToNative } from './bridge'

const origError = console.error.bind(console)
console.error = (...args: unknown[]) => {
  postToNative({ type: 'log', message: 'console.error: ' + args.map((a) => (a instanceof Error ? a.stack ?? a.message : String(a))).join(' ').slice(0, 2000) })
  origError(...args)
}
window.addEventListener('error', (e) => postToNative({ type: 'log', message: `error: ${e.message}` }))
window.addEventListener('unhandledrejection', (e) => postToNative({ type: 'log', message: `rejection: ${String(e.reason)}` }))

createRoot(document.getElementById('root')!).render(<App />)
