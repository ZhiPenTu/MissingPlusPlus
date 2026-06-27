/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Mirror MoodColor palette from Swift
        'mood-happy':     '#FFC857',
        'mood-joyful':    '#6EDC82',
        'mood-delighted': '#E91E63',
        'mood-sad':       '#5B7A99',
        'mood-longing':   '#9B72CF',
      },
    },
  },
  plugins: [],
}
