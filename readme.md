## Zootdeck fediverse desktop reader
https://donpdonp.github.io/zootdeck/

### Features
* Any number of columns
* Column Sources: User account, Site public feed
* per-column filtering on specific tags, or has an image
* linux/GTK+

### Roadmap
* create a post
* css themes: overall, per-tag, per-host
* osx/windows

### History
* 20190710 image only filter
* 20190706 profile image loading
* 20190613 oauth steps in config panel
* 20190604 network status indicator for each column
  *        better json escape handling
  *        append api path automatically
* 20190529 First release


### Build instructions
```
$ sudo apt install ragel libgtk-3-dev libcurl-dev libcurl4-openssl-dev libgumbo-dev libglfw3-dev

$ git clone https://github.com/donpdonp/zootdeck
Cloning into 'zootdeck'...

$ cd zootdeck

$ make
zig build

$ ./zootdeck
zootdeck linux x86_64 tid 7f565d1caf00
STATE: Init
```

