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

