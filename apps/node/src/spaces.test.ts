import { expect, it } from 'vitest';
import { spaceIcon } from './spaces';

const bytes = (text: string) => new TextEncoder().encode(text);
const svg = (body: string, box = '0 0 64 64') =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${box}">${body}</svg>`;
const drawn =
  '<defs><linearGradient id="g"><stop offset="0" stop-color="#fff"/></linearGradient></defs>' +
  '<rect width="64" height="64" fill="#1f4d3a"/><circle cx="32" cy="32" r="14" fill="url(#g)"/>';

it('takes the icon a Dot drew for its space', () => {
  expect(spaceIcon(bytes(svg(drawn)))).toBe(svg(drawn));
  expect(spaceIcon(bytes(`<?xml version="1.0" encoding="UTF-8"?>\n${svg(drawn)}\n`))).toContain(
    'viewBox="0 0 64 64"',
  );
  expect(spaceIcon(bytes(svg(drawn, '0 0 24.5 24.5')))).toContain('<circle');
});

it('refuses a space whose icon is missing or cannot be drawn safely', () => {
  const refused: (Uint8Array | undefined)[] = [
    undefined,
    bytes('<html></html>'),
    bytes(svg(drawn, '0 0 64 32')),
    bytes(svg('<text x="8" y="40">A</text>')),
    bytes(svg('<style>rect{fill:red}</style><rect width="64" height="64"/>')),
    bytes(svg('<script>alert(1)</script>')),
    bytes(svg('<image href="https://example.com/a.png" width="64" height="64"/>')),
    bytes(svg('<rect width="64" height="64" fill="url(https://example.com/a.svg#g)"/>')),
    bytes(svg('<use href="https://example.com/a.svg#g"/>')),
    bytes(svg('<rect width="64" height="64" onclick="go()"/>')),
    bytes(svg('<rect width="1" height="1"/>'.repeat(400))),
    Uint8Array.from([0x3c, 0x73, 0x76, 0x67, 0xff, 0xfe]),
  ];
  for (const icon of refused) expect(() => spaceIcon(icon)).toThrow(/icon\.svg/);
});
