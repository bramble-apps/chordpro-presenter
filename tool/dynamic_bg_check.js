// Compares the TV's wallpaper drawing (cast_receiver/public/dynamic_bg.js)
// with the app's: reads the app's frames as JSON on stdin
// ([{name, spec, t, w, h, rgba: [...]}]), draws each here and prints the
// biggest difference per frame. Run by test/dynamic_bg_cast_test.dart.
const R = require('../cast_receiver/public/dynamic_bg.js');
let input = '';
process.stdin.on('data', (d) => (input += d));
process.stdin.on('end', () => {
  const out = [];
  for (const f of JSON.parse(input)) {
    const mine = R.frame(f.spec, f.t, f.w, f.h);
    let max = 0, off = 0;
    for (let i = 0; i < mine.length; i++) {
      const d = Math.abs(mine[i] - f.rgba[i]);
      if (d > max) max = d;
      if (d > 1) off++;
    }
    out.push({ name: f.name, t: f.t, max, off });
  }
  console.log(JSON.stringify(out));
});
