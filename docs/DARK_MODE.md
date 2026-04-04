# Dark Mode Support

## Overview

EventManager now automatically adapts to your browser/system's dark mode preference using CSS media queries.

## How It Works

The application detects your system's color scheme preference and automatically applies the appropriate theme:

- **Light Mode** - Default Bootstrap styling
- **Dark Mode** - Custom dark color scheme that activates when your system is in dark mode

## Implementation

### Automatic Detection

Uses CSS `@media (prefers-color-scheme: dark)` to detect system preference.

**Browser detects from:**
- macOS: System Preferences → General → Appearance
- Windows: Settings → Personalization → Colors
- Linux: Desktop environment theme settings
- Browser settings (if system preference not available)

### Meta Tag

```html
<meta name="color-scheme" content="light dark">
```

This tells browsers that the app supports both color schemes.

### CSS Media Queries

All dark mode styles are wrapped in:
```css
@media (prefers-color-scheme: dark) {
  /* Dark mode styles */
}
```

## What Changes in Dark Mode

### Colors

**Light Mode:**
- Background: White (#ffffff)
- Text: Black/Dark gray
- Cards: White with light borders
- Forms: White backgrounds

**Dark Mode:**
- Background: Dark gray (#212529)
- Text: Light gray (#dee2e6)
- Cards: Darker gray (#2b3035)
- Forms: Dark backgrounds (#343a40)

### Components

✅ **Body background** - Dark gray  
✅ **Cards** - Dark with gray borders  
✅ **Modals** - Dark backgrounds  
✅ **Forms** - Dark input fields  
✅ **Alerts** - Adjusted colors for readability  
✅ **Tables** - Dark backgrounds with hover  
✅ **Footer** - Dark gray background  
✅ **List groups** - Dark item backgrounds  
✅ **Navbar** - Primary color (works in both modes)  

### Alerts in Dark Mode

Alerts are specially styled for dark mode readability:
- Info alerts: Blue background with white text
- Warning alerts: Dark yellow with light text
- Danger alerts: Dark red with pink text
- Success alerts: Dark green with light text

## Testing Dark Mode

### On macOS:
1. System Preferences → General → Appearance
2. Select "Dark"
3. Refresh EventManager in browser
4. See dark theme applied

### On Windows:
1. Settings → Personalization → Colors
2. Choose "Dark" under "Choose your mode"
3. Refresh EventManager
4. See dark theme

### In Chrome DevTools:
1. Open DevTools (F12)
2. Press Cmd+Shift+P (Mac) or Ctrl+Shift+P (Windows)
3. Type "dark" and select "Emulate CSS prefers-color-scheme: dark"
4. See instant switch to dark mode

### In Firefox DevTools:
1. Open DevTools (F12)
2. Click three-dot menu → Settings
3. Under "Advanced settings" find "prefers-color-scheme"
4. Select "dark"

## Browser Support

✅ **Chrome/Edge** 76+  
✅ **Firefox** 67+  
✅ **Safari** 12.1+  
✅ **Opera** 62+  

Fallback: Light mode for older browsers

## Customization

### Adjusting Dark Mode Colors

Edit `app/assets/stylesheets/application.bootstrap.scss`:

```scss
@media (prefers-color-scheme: dark) {
  body {
    background-color: #your-color;  // Change background
    color: #your-text-color;        // Change text
  }
  
  .card {
    background-color: #your-card-bg;
  }
}
```

### Adding Light Mode Overrides

```scss
@media (prefers-color-scheme: light) {
  .custom-element {
    background-color: #custom-light-color;
  }
}
```

### Force Dark Mode Always

To force dark mode regardless of system setting:

```scss
// Remove @media wrapper
body {
  background-color: #212529;
  color: #dee2e6;
}
```

## No JavaScript Required

This implementation uses **pure CSS** - no JavaScript needed!

Benefits:
- ⚡ Instant - no flash of wrong theme
- 🚀 Fast - no JS overhead
- 🎯 Simple - just CSS media queries
- 📱 Works everywhere - even with JS disabled

## Components Styled for Dark Mode

### Forms
- Input fields: Dark background, light text
- Selects: Dark dropdowns
- Focus states: Blue borders
- Placeholders: Muted gray

### Cards
- Dark backgrounds
- Gray borders
- Readable text contrast
- Proper spacing

### Modals
- Dark content areas
- Proper header colors
- Close buttons adapted

### Tables
- Dark backgrounds
- Hover states
- Good text contrast
- Border adjustments

### Badges
- Maintain color coding
- Readable in dark mode
- Proper contrast ratios

## Accessibility

All dark mode colors maintain **WCAG AA contrast ratios**:
- Normal text: 4.5:1 minimum
- Large text: 3:1 minimum
- UI components: 3:1 minimum

Colors chosen for:
✅ Readability  
✅ Accessibility  
✅ Professional appearance  
✅ Reduced eye strain  

## Future Enhancements

Possible additions:
- Manual dark mode toggle (override system)
- User preference storage in database
- Per-user theme selection
- Additional color schemes (blue, purple, etc.)
- High contrast mode
- Reduced motion support

## Troubleshooting

**Q: Dark mode not working?**
- Check your system is actually in dark mode
- Hard refresh browser (Cmd+Shift+R or Ctrl+Shift+F5)
- Clear browser cache
- Rebuild CSS: `docker compose exec web yarn build:css`

**Q: Some elements not dark?**
- Check if they have inline styles overriding
- May need additional CSS rules
- Open an issue with specific element

**Q: Want to disable dark mode?**
- Remove dark mode CSS from `application.bootstrap.scss`
- Rebuild CSS
- Remove color-scheme meta tag

## Verification

After implementation:
```bash
# Rebuild CSS
docker compose exec web yarn build:css

# Check for dark mode styles
docker compose exec web grep "prefers-color-scheme" app/assets/builds/application.css

# Should show 2 occurrences (dark and light media queries)
```

Visit http://localhost:3000 and toggle your system dark mode to see the magic! ✨

