![alt text](tatfi.jpg "tatfi")

# `tatfi` - TTF parsing in Zig

`tatfi` is an almost state-less, almost allocation-free, high level font parser of `TTF`, `OTF` and `AAT` written in pure Zig. It has no dependencies outside of the Zig standard library. It aims to be completely safe and completely panic free. If you find it panics in any compilation mode, please report it as a bug.

The start point of the Library is the `Face` struct, with its different methods. However, the individual font tables can be accessd individually. Also, any additional tables should be able to be requested by `Tag`, (although I have not tested that yet.)

## `ttf_parser`

Almost the entire Rust ecosystem depends on [`ttf_parser`](https://docs.rs/ttf-parser/latest/ttf_parser/) by the venerable [RazrFalcom](https://github.com/RazrFalcon). Any large enough Rust project you can think of that involves text somehow includes `ttf_parser` in its dependency tree.

`tatfi` is an almost line-by-line port of `ttf-parser`. Obviously, Zig does not offer the same memory safety guarantees Rust does, but I promise I have done my best. More eyes on the code would be helpful in tightening the screws.

## Status

`tatfi` is still a work in progress. The API surface is fairly complete. It is possible to build a rasterizer or a shaper on top of `tatfi`.

However, `ttf_parser` tests are not ported yet. Note that even with all `ttf_parser` tests ported, the crate actually depended on `rustybuzz` (and from there, the `HarfBuzz` test suite), for testing. Without actual real use of this library it is not possible to test exhaustively.

You can see the API surface on `main.zig`. If you'd like to help, please see any of the following topics.

### Tests and Benchmarks

There are currently no tests. Adding new tests or help in porting the tests and benchmarks would be super helpful.

### Better Errors

For most of the public API, either the data is there or it is not. Considering for most uses the font file is what it is, the error type does not really matter, and so most of the public API returns optionals. However, in some places, like for example `Face.outline_glyph` and the different methods it calls, could give more speciic errors. For example a hypothetical `error.GlyphNotFound` vs `error.EmptyGlyph` (like a space, which is really fine..) would be helpful.

Going over the API either as a user or as a writer and identifying places for more helpful errors rather than returning optionals would be of great help.

## License

The originai `ttf-parser` is dual licensed under the MIT License and the Apache 2.0 License. _This_ library is, however, licensed under the Mozilla Public License 2.0.

## Why Host at sr.ht

I am trying to wean off Microsoft and the rest of the Torment Nexus due to [their aiding and abetting an active occupation and genocide](https://www.un.org/unispal/document/a-hrc-59-23-from-economy-of-occupation-to-economy-of-genocide-report-special-rapporteur-francesca-albanese-palestine-2025/). (Search for Microsoft)
