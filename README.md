# Sonarr DB change checking

This script checks the Sonarr DB (nzbdrone.db) for changes from one execution to the next.

The first run will create an abridged db, which is used for checking specific values.

The items checked:
Show Name, Ended status
Episode Title,Season, Episode Number, air date

Any found changes will show the previous and current information. 

## Underlying tools

The following tools are needed

```
sqlite3, sqldiff
```

## How to get them
```
https://www.sqlite.org/index.html
$ apt-get install sqlite3 sqlite3-tools
```

## Current Issues
```
The column width for each section is set by the first line displayed. Spacing can end up being messed up

The code isn't perfect and always improving. If you have input, please let me know here.

Deleted episodes for a deleted shows still list out individually. Should be skipped during the deleted episode list. Not sure why, but haven't had time to debug it.
```


## Output Examples
```

*** Deleted Episodes ***
Show                                  Season      Episode     Title       Airdate
------------------------------------  ----------  ----------  ----------  ----------
DC Super Hero Girls: Super Hero High  5           8           Hackgirl    2018-09-20


*** New Episodes ***
Show                Season      Episode     Title           Airdate
------------------  ----------  ----------  --------------  ----------
American Housewife  5           7           Under Pressure  2021-01-27
The Goldbergs (201  8           9           Cocoon          2021-01-27


======================
Family Guy
--------------
S:19 E:15
Title: TBA => Customer of the Week


======================
Shark Tank
--------------
S:12 E:16
Title: Episode 16 => Simply Good Jars, Pinch Me Therapy Dough, Muff Waders, BusyBaby Mat



*** Deleted Series ***
Showname        Status
--------------  ----------
Schitt's Creek  Ended


*** New Series ***
Showname           Status
----------         ----------
Perry Mason (2020) Ongoing


*** Series Status Changes ***
Showname         Previous Status  Current Status
---------------  ----------  ----------
Carmen Sandiego  Ongoing     Ended

