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

Note: The code isn't perfect and always improving. If you have input, please let me know here.

## Output Examples

*** Previous Episode Information ***

Showname       Season      Episode     title                                                                        Airdate

-------------  ----------  ----------  ---------------------------------------------------------------------------  ----------

Cosmos (2014)  0           1           Celebrating Carl Sagan: A Selection from the Library of Congress Dedication  2014-06-10

Cosmos (2014)  0           2           Cosmos: A Spacetime Odyssey at Comic-Con 2013                                

*** Current Episode Information ***

Showname       Season      Episode     title                                                                        Airdate

-------------  ----------  ----------  ---------------------------------------------------------------------------  ----------

Cosmos (2014)  0           1           Celebrating Carl Sagan: A Selection from the Library of Congress Dedication  2014-06-10

Cosmos (2014)  0           2           Cosmos: A Spacetime Odyssey at Comic-Con 2013                                2014-06-10

Cosmos (2014)  0           3           Cosmos: A Spacetime Odyssey - The Voyage Continues                           2014-06-10

Cosmos (2014)  0           4           Cosmos: A Spacetime Odyssey - The Cosmic Calendar                            2014-06-10



*** Previous Series Information ***

Showname    Ended

11.22.63    0

Breaking B  0

*** Current Series Information ***

Showname    Ended

11.22.63    1

Arrested D  1

Batman Bey  1

Batman: Th  1

Big Little  1

Breaking B  1

