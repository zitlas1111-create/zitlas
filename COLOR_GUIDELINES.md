# ZITLAS Color Guidelines

## Brand Psychology

- Orange means action, motivation, energy.
- Green means health, progress, success.
- Black means premium focus.
- Cyan means AI intelligence.

## Official Tokens

Use the global tokens from `frontend/assets/css/theme.css`.

```css
:root {
  --bg-primary: #000000;
  --bg-card: #111111;
  --bg-card-light: #171717;

  --primary: #FF8C00;
  --primary-hover: #FFA726;
  --primary-dark: #E67E22;

  --success: #22C55E;
  --success-dark: #16A34A;

  --ai-accent: #00C2FF;

  --text-primary: #FFFFFF;
  --text-secondary: #9CA3AF;
  --text-muted: #6B7280;

  --border: #222222;
  --shadow: rgba(255,140,0,0.20);
}
```

## Color Usage Rules

### Orange

Use orange for:

- Primary buttons
- Active navbar item
- CTA buttons
- Streak cards
- Calories
- Prices
- Start Assessment button
- Important actions
- Progress highlights

Do not use orange for body text.

### Green

Use green for:

- Completed workouts
- Goal achieved states
- Weight lost
- Success badges
- Online status
- Progress bars
- Completed tasks
- Positive indicators

### Cyan

Use cyan only for:

- AI Generated badges
- AI Insights
- AI Coach tags
- Smart Recommendations
- AI cards

Do not use cyan for buttons.

### White And Gray

Use white and gray for:

- Headings
- Body copy
- Descriptions
- Secondary information
- Labels
- Placeholders

## Reusable Utility Classes

```html
<span class="text-success">Completed</span>
<span class="text-primary">Action</span>
<span class="text-ai">AI Insight</span>

<div class="bg-card">...</div>
<button class="btn-primary">Start Assessment</button>
<span class="badge-success">Goal Achieved</span>
<span class="badge-ai">AI Generated</span>
```

## Component Rules

Cards:

```css
background: var(--bg-card);
border: 1px solid var(--border);
border-radius: 22px;
```

Primary buttons:

```css
background: var(--primary);
box-shadow: 0 0 30px rgba(255,140,0,0.25);
```

Success states:

```css
color: var(--success);
```

AI badges:

```css
background: rgba(0,194,255,0.12);
color: var(--ai-accent);
```

## Migration Notes

- Prefer official tokens over page-local hex values.
- Keep orange for action, not paragraph text.
- Keep cyan rare and reserved for AI meaning.
- Use green only for positive/progress states.
- Avoid introducing new purple, blue, yellow, beige, or red brand accents unless a future design token is approved.
