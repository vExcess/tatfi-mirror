# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

### Fixed

- Expose `SequenceRule` and `ChainedSequenceRule` and added missing `parse` methods that were not checked before. Damn you lazy compilation
- Adjust `class_needle` paramter in `aat.ExtendedStateTable` to `u16` instead of `u8`. It doesn't really matter but it aligns better with `ttf-parser` API.

### Added 

- Expose `Feature`
- `find_substitute` public method for `FeatureVariations`.
- `find_index` public method for `FeatureVariations`.
- Expose `Ligature` 
- Expose the generic paramter of `LookupTable`s.

## 0.1.1 - 2026-02-02

### Added

- This Changelog
