GITEPOCH=$(shell git log -1 --format="%at")
TODAY=$(shell date +%Y.%m.%d -d @${GITEPOCH})
DIST=zootdeck-linux-`uname -i`-${TODAY}
DISTDEB=zootdeck_0.6.5-1
ZIG=zig

build:
	${ZIG} build -freference-trace -fincremental --summary all

format:
	${ZIG} fmt src

run: build
	./zig-out/bin/zootdeck

test:
	zig build test

test-each:
	find src -name \*zig -print -exec zig test {} \;

dist:
	mkdir ${DIST}
	cp -r ./zig-out/bin/zootdeck img ${DIST}/
	cp config.json.example ${DIST}/config.json
	tar czf ${DIST}.tar.gz ${DIST}
	ls -l ${DIST}
	file ${DIST}.tar.gz

deb:
	mkdir -p ${DISTDEB}/opt/
	cp -r img ${DISTDEB}/opt/
	mkdir -p ${DISTDEB}/usr/bin
	cp -r zig-out/bin/zootdeck ${DISTDEB}/usr/bin/
	mkdir -p ${DISTDEB}/DEBIAN
	cp control.deb ${DISTDEB}/DEBIAN/control
	ls -lR ${DISTDEB}
	dpkg-deb --build ${DISTDEB}
	mv ${DISTDEB}.deb ${DISTDEB}-amd64.deb

push:
	jj git push --allow-new -c @-
	jj bookmark set main -r @-
	jj git push --allow-new --bookmark main

