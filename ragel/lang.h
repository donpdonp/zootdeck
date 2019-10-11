struct urlPoints { 
  int scheme_pos;
  int loc_pos;
 };

struct urlPoints* url(char* uri, struct urlPoints* urlp);
