# Website

The TruFocus marketing site: one static page, `index.html`, with no build step.

A fixed WebGL stage (three.js 0.169.0, loaded from jsDelivr) runs one particle system that moves between formations as you scroll: the focus point (the app icon), a calm horizon for the outcomes, the noise, and the tunnel behind the count-up clock. Right after the hero, "A day in TruFocus" pins an iPhone and walks through eleven moments of a real day. Each screen is drawn at 390 × 844 points from the app's SwiftUI views and copy (brain dump, focus, shield, Reply pass, think, switch, rest, Lock Screen, scoreboard), and scroll drives what happens on screen. The product, details and research sections use the app's paper palette and follow the viewer's light or dark theme. Without WebGL the page shows a static ember ring and everything else works.

## Preview

```sh
python3 -m http.server 8000 --directory website
```

Then open http://localhost:8000.

## Deploy

Any static host works. On Vercel, import the repo and set **Root Directory** to `website` with no framework preset and no build command.

## Before launch

- **Invite form.** It validates the address and then tells the visitor that requests open at launch. Nothing is sent. Point the submit handler (the `invite` form in the first `<script>`) at the beta list.
- **Numbers.** The rest lengths, doom-scroll limits, scroll budget and juggling limit match the defaults in `Packages/TrueFocusKit`. If those defaults change, update the Details section.
- **Research.** Each card links to its source; the full list is in the footer.
