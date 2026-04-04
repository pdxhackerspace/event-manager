# Bootstrap Customization Guide

## Current Setup

We're using **pre-compiled Bootstrap CSS** to avoid deprecation warnings from Bootstrap 5.3's SCSS source code.

**File:** `app/assets/stylesheets/application.bootstrap.scss`
```scss
@import 'bootstrap/dist/css/bootstrap.min.css';
@import 'bootstrap-icons/font/bootstrap-icons.css';
```

**Benefits:**
- ✅ Zero deprecation warnings
- ✅ Faster build times
- ✅ No dealing with Bootstrap's internal SCSS complexity

**Trade-off:**
- ❌ Can't customize Bootstrap variables (colors, spacing, etc.)

---

## If You Need Customization

If you want to customize Bootstrap's colors, spacing, or other variables, you have two options:

### Option 1: Override with CSS (Simple)

Add your custom styles in `application.bootstrap.scss`:

```scss
@import 'bootstrap/dist/css/bootstrap.min.css';
@import 'bootstrap-icons/font/bootstrap-icons.css';

/* Custom overrides */
:root {
  --bs-primary: #ff6b6b;
  --bs-secondary: #4ecdc4;
}

.btn-primary {
  background-color: #ff6b6b;
  border-color: #ff6b6b;
}
```

### Option 2: Compile from SCSS Source (Advanced)

If you REALLY need to customize Bootstrap variables, accept the deprecation warnings until Bootstrap 6:

1. Create `app/assets/stylesheets/custom.scss`:
```scss
// Custom Bootstrap variable overrides
$primary: #ff6b6b;
$secondary: #4ecdc4;
$border-radius: 0.5rem;
$font-family-base: 'Inter', system-ui, -apple-system, sans-serif;

// Import Bootstrap SCSS
@import 'bootstrap/scss/bootstrap';
```

2. Update `application.bootstrap.scss`:
```scss
@import 'custom';
@import 'bootstrap-icons/font/bootstrap-icons';
```

3. Accept the deprecation warnings (they're from Bootstrap, not your code)
4. Add `--quiet-deps` back to hide dependency warnings if desired

---

## Why the Warnings Exist

Bootstrap 5.3 uses **old Sass syntax** that will be removed in Dart Sass 3.0:

- Old: `@import`, `mix()`, `red()`, `blue()`, `unit()`
- New: `@use`, `color.mix()`, `color.channel()`, `math.unit()`

**Bootstrap's Status:**
- Bootstrap 5.x: Still uses old syntax
- Bootstrap 6.x: Will use modern Sass (in development)

**Our code is modern** - we used `@use` syntax. The warnings are from Bootstrap's internal files, which we can't fix.

---

## Recommended Approach

For most projects: **Use pre-compiled CSS** (current setup)

Only compile from SCSS if you need to:
- Customize Bootstrap variables
- Tree-shake unused Bootstrap components
- Use Bootstrap's SCSS mixins in your custom styles

The deprecation warnings won't break your app - they're just informational messages from Sass about future changes.

---

## Alternative: Use CDN

If you don't need to customize Bootstrap at all, you could skip Yarn entirely:

**app/views/layouts/application.html.erb:**
```erb
<head>
  <!-- Bootstrap CSS via CDN -->
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.css">
  
  <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
</head>
<body>
  <!-- Content -->
  
  <!-- Bootstrap JS via CDN -->
  <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
</body>
```

This gives you the fastest page loads with Bootstrap's CDN.

