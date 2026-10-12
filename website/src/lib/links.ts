const repo = 'https://github.com/kmrifat/devvault';

export const links = {
  repo,
  releases: `${repo}/releases/latest`,
  mac: `${repo}/releases/latest/download/DevVault-macos.dmg`,
  linux: `${repo}/releases/latest/download/devvault-linux-x64.AppImage`,
  license: `${repo}/blob/main/LICENSE`,
  issues: `${repo}/issues`,
  security: `${repo}/blob/main/docs/format/SPEC.md`,
};

// Formspree form URL for the team survey (https://formspree.io/f/<id>).
// Empty until the form exists; the survey says so instead of sending.
export const surveyEndpoint = '';
