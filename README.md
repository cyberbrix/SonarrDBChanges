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
sqlite3,sqldiff
```

## How to get them
```
SQLite - https://www.sqlite.org/index.html/
apt-get install sqlite3
```

## Current Issues
```
The column width for each section is set by the first line displayed.

The other option I'm exploring is to list episode by episode, only mentioning the different fields, but this would take a lot more looping and sql queries.


The code isn't perfect and always improving. If you have input, please let me know here.
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

*** Previous Episode Information ***
Show             Season      Episode     Title       Airdate
---------------  ----------  ----------  ----------  ----------
Carmen Sandiego  4           1           TBA         2021-01-15
Carmen Sandiego  4           2           TBA         2021-01-15
Carmen Sandiego  4           3           TBA         2021-01-15
Family Guy       19          10          Fecal Matt  2021-02-14
Law & Order: Sp  22          5           Turn Me On  2021-01-14


*** Current Episode Information ***
Show             Season      Episode     Title                      Airdate
---------------  ----------  ----------  -------------------------  ----------
Carmen Sandiego  4           1           The Beijing Bullion Caper  2021-01-15
Carmen Sandiego  4           2           The Big Bad Ivy Caper      2021-01-15
Carmen Sandiego  4           3           The Robo Caper             2021-01-15
Family Guy       19          10          Fecal Matters              2021-01-17
Law & Order: Sp  22          5           Turn Me On, Take Me Priva  2021-01-14


*** Deleted Series ***
Showname        Status
--------------  ----------
Schitt's Creek  Ended


*** New Series ***
Showname           Status
----------         ----------
Perry Mason (2020) Ongoing


*** Modified Series - Previous  ***
Showname         Status
---------------  ----------
Carmen Sandiego  Ongoing


*** Modified Series - Current ***
Showname         Status
---------------  ----------
Carmen Sandiego  Ended
