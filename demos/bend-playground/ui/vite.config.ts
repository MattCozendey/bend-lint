import path from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

const backend = `http://127.0.0.1:${process.env.PORT || 3000}`

export default defineConfig({
  base: process.env.VITE_STATIC === 'true' ? process.env.PAGES_BASE : '/',
  plugins: [react(), tailwindcss()],
  resolve: { alias: { '@': path.resolve(import.meta.dirname, './src') } },
  build: { outDir: process.env.VITE_STATIC === 'true' ? '../build/pages' : '../build/ui', emptyOutDir: true },
  server: {
    proxy: {
      '/api': backend,
      '/output': backend,
      '/rubik-engine.js': backend,
      '/times-table-engine.js': backend,
      ...Object.fromEntries(['fourier','sorting','shakespeare','polar'].map(n => [`/${n}-engine.js`, backend])),
    },
  },
})
