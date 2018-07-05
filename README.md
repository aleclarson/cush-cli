# cush-cli v0.0.3

The easiest way to bundle your project using `cush`.

```sh
cush <main> -o <dest> -t <platform> [-p]
```

&nbsp;

The `platform` may exist in `dest` instead of being
specified separately. The only difference is the bundle path.

```sh
cush index.js -o bundle.web.js

# almost identical to:
cush index.js -o bundle.js -t web
```

&nbsp;

The `-p` flag minifies the bundle and exits after the first build.
Additionally, the bundle name has a content hash. This is known as
the "production" bundle.

## Install

```sh
npm install -g cush-cli
```
