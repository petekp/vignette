import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Relative base so the built page loads from a file:// URL inside the app bundle.
export default defineConfig({
  plugins: [react()],
  base: './',
  build: { outDir: 'dist', emptyOutDir: true },
})
