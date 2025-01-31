GITEPOCH=$(shell git log -1 --format="%at")
TODAY=$(shell date +%Y.%m.%d -d @${GITEPOCH})
DIST=zootdeck-linux-`uname -i`-${TODAY}
ZIG=/opt/zig/0.13.0/zig
#ZIG=/opt/zig/0.14.0-dev/zig

build:
	${ZIG} build -freference-trace

format:
	${ZIG} fmt src

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
