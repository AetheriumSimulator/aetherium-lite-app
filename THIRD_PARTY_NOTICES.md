# Third-Party Notices

This notice is a source inventory for the app repository. It is not legal advice.

The MIT license in `LICENSE` applies only to original Aetherium Lite code in this repository. Runtime components and generated binaries keep their upstream licenses.

## Runtime Components

| Component | Upstream | License notes |
| --- | --- | --- |
| Proton | https://github.com/ValveSoftware/Proton | Top-level Proton distribution uses BSD-3-Clause style terms plus bundled third-party licenses. |
| Wine | https://gitlab.winehq.org/wine/wine | LGPL-2.1-or-later. Modified Wine binaries require corresponding source and license notices. |
| Box64 | https://github.com/ptitSeb/box64 | MIT. Preserve copyright and license notices. |
| DXVK | https://github.com/doitsujin/dxvk | zlib/libpng style license in Proton notices. |
| vkd3d-proton | https://github.com/HansKristian-Work/vkd3d-proton | LGPL-2.1. Modified binaries require corresponding source and license notices. |
| FAudio | https://github.com/FNA-XNA/FAudio | zlib license in Proton notices. |
| GStreamer components | https://gstreamer.freedesktop.org/ | LGPL components may be present in Proton runtime distributions. |
| wine-mono | https://github.com/madewokherd/wine-mono | Mixed notices in Proton distribution; commonly MIT/LGPL/GPL-with-exception subcomponents. |
| wine-gecko | https://sourceforge.net/p/wine/wine-gecko | MPL-2.0 according to Proton distribution notices. |
| Bundled fonts in Proton distributions | See Proton `dist.LICENSE` | SIL Open Font License and other permissive font notices may apply. |

## Distribution Checklist

- Include upstream license texts and notices with any binary/runtime release.
- Publish corresponding source and exact patch set for LGPL-covered modified components such as Wine and vkd3d-proton.
- Prefer dynamic/shared-library boundaries for LGPL components.
- Do not ship proprietary game assets, installers, launcher payloads, account data, or signing materials.
- Keep large generated runtime payloads out of the app source repository; use a dedicated runtime source repository and release artifacts.
