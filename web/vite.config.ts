import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Relative base: the app serves the built page from a tokened path on its loopback server.
export default defineConfig({
  plugins: [react()],
  base: './',
  build: { outDir: 'dist', emptyOutDir: true },
})
