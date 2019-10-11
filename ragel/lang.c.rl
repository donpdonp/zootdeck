#include <string.h>
#include "lang.h"

%%{
	machine uri;

	action scheme { urlp->scheme_pos = p-uri; }
	action loc { urlp->loc_pos = p-uri; }
	action item { }
	action query { }
	action last {  }
	action nothing { }

	main :=
		# Scheme machine. This is ambiguous with the item machine. We commit
		# to the scheme machine on colon.
		( [^:/?#]+ ':' @(colon,1) @scheme )?

		# Location machine. This is ambiguous with the item machine. We remain
		# ambiguous until a second slash, at that point and all points after
		# we place a higher priority on staying in the location machine over
		# moving into the item machine.
		( ( '/' ( '/' [^/?#]* ) $(loc,1) ) %loc %/loc )? 

		# Item machine. Ambiguous with both scheme and location, which both
		# get a higher priority on the characters causing ambiguity.
		( ( [^?#]+ ) $(loc,0) $(colon,0) %item %/item )? 

		# Last two components, the characters that initiate these machines are
		# not supported in any previous components, therefore there are no
		# ambiguities introduced by these parts.
		( '?' [^#]* %query %/query)?
		( '#' any* %/last )?;
}%%

%% write data;

struct urlPoints* url(char* uri, struct urlPoints* urlp) {
  char *p = uri, *pe = uri + strlen( uri );
  char* eof = pe;
  int cs;

  %% write init;
  %% write exec;

  return urlp;
}

/*
int main(int argc, char**argv)
{
  char* arg = argv[1];
  struct urlPoints it;

  printf("parsing %s\n", arg);
  url(arg, &it);

  char scratch[512]; 
  strncpy(scratch, arg, it.scheme_pos);
  printf("scheme %s\n", scratch);
  strncpy(scratch, arg+it.scheme_pos+1, it.loc_pos - it.scheme_pos);
  printf("scheme %s\n", scratch);
}
*/
