TODAY=`date +'%Y.%m.%d'`
DIST=zootdeck-${TODAY}

build:
	zig build

run: build
	./zootdeck

push:
	pijul push donpdonp@nest.pijul.com:donpdonp/tootdeck

dist:
	mkdir ${DIST}
	cp -r zootdeck themes theme.css img glade ${DIST}/
	cp config.json.example ${DIST}/config.json
	tar czf ${DIST}.tar.gz ${DIST}
	ls -l ${DIST}
	file ${DIST}.tar.gz
