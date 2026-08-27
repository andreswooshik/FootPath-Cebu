/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    './portal/templates/**/*.html',
    './portal/static/portal/**/*.js',
  ],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      },
    },
  },
  plugins: [],
};
