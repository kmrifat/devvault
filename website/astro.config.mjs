import { defineConfig } from 'astro/config';

// Served by GitHub Pages at kmrifat.github.io/devvault until there's a domain.
export default defineConfig({
  site: 'https://kmrifat.github.io',
  base: '/devvault',
  devToolbar: { enabled: false },
});
