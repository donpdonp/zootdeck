
build:
	zig build

run: build
	./zootdeck

push:
	pijul push donpdonp@nest.pijul.com:donpdonp/tootdeck
