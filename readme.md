## Zootdeck fediverse desktop reader
https://donpdonp.github.io/zootdeck/

### Features
* Any number of columns
* Column Sources: User account, Site public feed
* linux/GTK+

### Roadmap
* per-column filter language
* create a post
* css themes: overall, per-tag, per-host
* osx/windows

### History
20190613 oauth steps in config panel
20190604 network status indicator for each column
         better json escape handling
         append api path automatically

20190529 First release


### Build instructions
```
$ git clone https://github.com/donpdonp/zootdeck
Cloning into 'zootdeck'...

$ cd zootdeck

$ make
zig build

$ ./zootdeck
zootdeck linux x86_64 tid 7f565d1caf00
STATE: Init
```