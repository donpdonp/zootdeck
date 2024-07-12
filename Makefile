GITEPOCH=$(shell git log -1 --format="%at")
TODAY=$(shell date +%Y.%m.%d -d @${GITEPOCH})
DIST=zootdeck-linux-`uname -i`-${TODAY}

build: ragel/lang.c
	zig build -freference-trace

ragel/lang.c: ragel/lang.c.rl
	ragel -o ragel/lang.c ragel/lang.c.rl

format:
	zig fmt src

run: build
	./zig-out/bin/zootdeck

push:
	pijul push donpdonp@nest.pijul.com:donpdonp/tootdeck

test:
	find src -name \*zig -print -exec zig test {} \;

dist:
	mkdir ${DIST}
	cp -r ./zig-out/bin/zootdeck theme.css img glade ${DIST}/
	cp config.json.example ${DIST}/config.json
	tar czf ${DIST}.tar.gz ${DIST}
	ls -l ${DIST}
	file ${DIST}.tar.gz
