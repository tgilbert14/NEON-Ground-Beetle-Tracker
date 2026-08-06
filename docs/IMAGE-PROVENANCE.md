# Ground Beetle cover image provenance

Status: **CURRENT / SUITE LIVING POSTER ART V2**

The public Pages cover and the in-app first-run poster use the same static
illustration. It is an editorial invitation, never a field photograph, NEON
observation, specimen record, or data visualization.

## Production Living Poster illustration

- Primary file: `docs/assets/ground-beetle-living-poster.png`
- Dimensions: 1672 x 941 PNG
- Bytes: 3,269,343
- SHA-256:
  `9d5fbbe03079f09c838b3d6c6221518d82c47c3c1dd2818e3c7f2a55afeee27a`
- Tool: OpenAI built-in image generation
- Generated: 2026-07-23
- Use: lossless fallback and source for responsive derivatives
- Alt text: “Editorial screenprint of a ground beetle crossing moss and leaf
  litter beside a pitfall trap embedded in a forest-floor cutaway.”
- Surface policy: meaningful alt text and this durable receipt carry the image's
  editorial-art status; the cover intentionally has no separate illustration badge.

Generation brief:

> Create an original, highly finished 16:9 editorial screenprint about NEON
> ground beetle pitfall sampling. Show a nocturnal forest floor as a shallow
> cutaway with moss, leaf litter, roots, and dark soil strata. Make one
> anatomically plausible carabid ground beetle the monumental hero, alive and
> crossing the surface beside—not falling into—a simple pitfall cup embedded
> flush with the soil. Use bold analog screenprint/linocut collage, tactile ink,
> paper grain, halftone speckle, carved edges, and a limited palette of
> near-black forest green, moss/chartreuse, oxidized copper, and warm parchment.
> Keep the left 30–35% dark and quiet for page copy; place the beetle
> center-right and the cup lower-right. No text, labels, border, logo, watermark,
> photographic treatment, generic scarab anatomy, fantasy glow, or animation
> cues.

The selected image was reviewed for recognizable carabid form, an unambiguous
flush-buried pitfall cup, a non-photographic treatment, and useful desktop and
mobile crops.

## Responsive delivery files

The WebP derivatives were created mechanically from the production PNG with
Pillow 12.2.0; no generative changes were made after the image was selected.

| Surface | File | Dimensions | Bytes | SHA-256 |
|---|---|---:|---:|---|
| Pages full | `docs/assets/ground-beetle-living-poster.webp` | 1672 x 941 | 571,042 | `287ee35f15454493b0858df70f47aa236c9a1671621d2f147899401a02800d82` |
| Pages compact | `docs/assets/ground-beetle-living-poster-840.webp` | 840 x 473 | 140,234 | `f23c8781035b95b59c9eb019b644986e96674a7899f38ab300db3f223464a367` |
| Connect fallback | `www/assets/ground-beetle-living-poster.png` | 1672 x 941 | 3,269,343 | `9d5fbbe03079f09c838b3d6c6221518d82c47c3c1dd2818e3c7f2a55afeee27a` |
| Connect full | `www/assets/ground-beetle-living-poster.webp` | 1672 x 941 | 571,042 | `287ee35f15454493b0858df70f47aa236c9a1671621d2f147899401a02800d82` |
| Connect compact | `www/assets/ground-beetle-living-poster-840.webp` | 840 x 473 | 140,234 | `f23c8781035b95b59c9eb019b644986e96674a7899f38ab300db3f223464a367` |

The Pages and Connect assets are byte-identical copies. The full WebP stays
below 600 KB and the compact version is the first-choice mobile download.

## Release contract

`scripts/check_cover.mjs` pins all six delivery assets, verifies the 1672 x 941
source dimensions, and requires the same hook, promise, CTA, meaningful alt text,
absence of a redundant illustration badge, and scientific claim boundary on Pages
and in the app. The main illustration
has no CSS or JavaScript animation.
