export const standalone = import.meta.env.VITE_STATIC === 'true'
export const asset = (path: string) => `${import.meta.env.BASE_URL}${path}`
