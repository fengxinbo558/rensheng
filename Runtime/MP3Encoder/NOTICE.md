# LAME MP3 encoder

This directory contains an unmodified Apple Silicon build of LAME 3.100.

- Project: <https://lame.sourceforge.io/>
- Source archive: `lame-3.100.tar.gz`
- Source SHA-256: `ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e`
- Binary SHA-256: `72614767c8ee7430bf539a0b1e69d60395ac61679aa20b98d640ec71fae26f1f`
- License: GNU Library General Public License v2; see `COPYING`.

The binary was built from the included source without source modifications:

```sh
./configure --disable-shared --enable-static \
  CFLAGS='-O2 -arch arm64 -mmacosx-version-min=14.0' \
  LDFLAGS='-arch arm64 -mmacosx-version-min=14.0'
make -j4
```
