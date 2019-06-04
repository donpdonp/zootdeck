## mastodon/fediverse desktop reader

* Any number of columns
* Column Sources: User account, Site public feed
* GTK+

## Roadmap
* per-column filter language
* create a post
* css themes: overall, per-tag, per-host

## History
20190604 network status indicator for each column
         better json escape handling
         append api path automatically

20190529 First release


Authenticated account access is supported but there is no UI for it yet.
If you want to see a column from your own feed, follow these steps to get
and access token to put into the config.json.

## steps to get an access token from a mastodon site

### establish a client_id and client_secret
$ curl 'https://mastodon.example/api/v1/apps' -d 'client_name=zootdeck' -d 'redirect_uris=urn:ietf:wg:oauth:2.0:oob' -d 'scopes=read'
{"id":"30500","name":"zootdeck","website":null,"redirect_uri":"urn:ietf:wg:oauth:2.0:oob","client_id":"...","client_secret":"...","vapid_key":"..."}

### password authentication
Use your account email in the username field
$ curl 'https://mastodon..example/oauth/token' -d 'client_id=...' -d 'client_secret=...' -d 'grant_type=password' -d
 'username=...' -d 'password=...'
{"access_token":"<token>","token_type":"Bearer","scope":"read","created_at":1559065381}

### set in config.json
Put the access_token value in the token field of config.json
```
    "title" : "youruser@mastodon.example",
    "url" : "https://mastodon.example/api/v1/timelines/home",
    "token" : "token here - see readme",
    "last_check" : 1558112041}]
```


