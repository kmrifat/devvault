// Path under the site's base ("/devvault" on GitHub Pages).
export const u = (path: string) =>
  `${import.meta.env.BASE_URL.replace(/\/$/, '')}/${path.replace(/^\//, '')}`;
