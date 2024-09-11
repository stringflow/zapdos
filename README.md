# zapdos

A minimal screenshot utility for X11. zapdos was written to replace [maim](https://github.com/naelstrof/maim) in my workflow.

Features:
- Exports PNG screenshots to stdout to then be piped elsewhere (file or clipboard)
- Supports multiple kinds of selections: active window, custom region

# Dependencies
Compile-time:
 - zig v0.13.0
 - libc
 - xorg

Runtime:
 - ffmpeg

# Cloning and Compiling
Clone the repository
```
$ git clone https://github.com/stringflow/zapdos
```
Change the directory to zapdos
```
$ cd zapdos
```
Compile
```
$ zig build
```
Install the binary to PATH
```
$ cp zig-out/bin/zapdos ~/bin
```