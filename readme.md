## Zootdeck fediverse desktop reader
https://donpdonp.github.io/zootdeck/

### Features
* Any number of columns
* Column Sources: User account, Site public feed
* per-column filtering on specific tags, or has an image
* linux/GTK+

### Roadmap
* initial QT support
* initial lemmy support
* create a post
* css themes: overall, per-tag, per-host
* osx/windows

### Build instructions
```
$ sudo apt install ragel libgtk-3-dev libcurl4-openssl-dev libgumbo-dev

$ git clone https://github.com/donpdonp/zootdeck
Cloning into 'zootdeck'...

$ cd zootdeck

$ make
zig build

$ ./zig-out/bin/zootdeck
zootdeck linux x86_64 tid 7f565d1caf00
```
`zig-out/bin/zootdeck` is a stand-alone binary that can be copied to `/usr/local/bin/` or where ever you like.

