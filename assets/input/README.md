# assets/input — ControllerButton Art

SVG button-cap art used by the Pro Control Deck overview and bar widget.
Vendored from [icculus/ControllerImage](https://github.com/icculus/ControllerImage)
(the redistributable art assets; the SDL3 C library is not used).

## Sources

- **Kenney "Input Prompts" (1.0)**, created/distributed by Kenney (www.kenney.nl),
  license: Creative Commons Zero, CC0
  (http://creativecommons.org/publicdomain/zero/1.0/). Crediting "Kenney" or
  "www.kenney.nl" is optional but appreciated.

- ControllerImage's art is public domain per its `DATA-LICENSE.txt`.

Sets vendored:
- `xbox360/` — A/B/X/Y face caps (as n/s/w/e), dpad, shoulder + trigger caps
- `ps3/`     — △/×/□/○ face caps (as n/s/w/e), dpad, shoulder + trigger caps,
               stick caps
- `switchpro/` — dpad cap

Button naming follows ControllerImage's SDL3 physical-position convention:
`n` = top (Y / △), `s` = bottom (A / ×), `w` = left (X / □), `e` = right (B / ○).