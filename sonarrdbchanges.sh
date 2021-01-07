#!/bin/bash
# This script will show changes in the sonarr database

#check if sqlite3 installed
if ! type sqlite3 &> /dev/null
then
  echo -e "\nsqlite3 is not installed"
  exit 1
fi

if ! type sqldiff &> /dev/null
then
  echo -e "\nsqldiff is not installed"
  exit 1
fi


# specify the sonarr db location
#sonarrdbpath="/home/$USER/.config/NzbDrone/nzbdrone.db"

# Find the sonarr db
sonarrdbpath=`find / -name "nzbdrone.db" -type f  -printf '%T+ %p\n'  2>/dev/null | grep -iv "find:/radarr" | sort -r | head -1 | cut -d' ' -f2-`
if [[ ! -r "$sonarrdbpath" ]]
then
  echo -e "\nnzbdone.db is not found or accessible"
  exit 1
fi

# Test if db tables are accessable
sonarrtables=`sqlite3 "$sonarrdbpath" ".tables"`
if [[ $sonarrtables != *"Episodes"* ]] || [[ $sonarrtables != *"Series"* ]]
then
  echo -e "\nThe needed tables were not found (Episodes and Series). $sonarrdbpath may not be the right database"
  exit 1
fi 

# Check of existing comaprison db for reference
comparisondb="/home/$USER/.sonarrepisodeinfo.db"
if [[ ! -r "$comparisondb" ]]
then
  # no comparison needed, create the new db and exit
  sqlite3 $comparisondb "ATTACH DATABASE '$sonarrdbpath' AS 'nzbdrone';CREATE TABLE EpisodeList (Showname TEXT,Season INTEGER,Episode INTEGER,Title TEXT,Airdate TEXT);CREATE TABLE SeriesStatus (Showname TEXT,Ended INTEGER);INSERT INTO EpisodeList SELECT B.Title, A.seasonnumber, A.episodenumber, A.title, A.airdate FROM nzbdrone.Episodes A LEFT JOIN nzbdrone.Series B ON A.SeriesID = B.Id;INSERT INTO SeriesStatus SELECT Title,Status FROM nzbdrone.Series;"
  exit 0
fi

# Create smaller database of current data to compare
tempdb="/home/$USER/.sonarrtemp.db"
sqlite3 $tempdb "ATTACH DATABASE '$sonarrdbpath' AS 'nzbdrone';CREATE TABLE EpisodeList (Showname TEXT,Season INTEGER,Episode INTEGER,title TEXT,Airdate TEXT);CREATE TABLE SeriesStatus (Showname TEXT,Ended INTEGER);INSERT INTO EpisodeList SELECT B.Title, A.seasonnumber, A.episodenumber, A.title, A.airdate FROM nzbdrone.Episodes A LEFT JOIN nzbdrone.Series B ON A.SeriesID = B.Id;INSERT INTO SeriesStatus SELECT Title,Status FROM nzbdrone.Series;"

# Build array of changed episodes
while read -r line ; do
  # find rowids of changes
  rowid=${line##*=}
  rowid=${rowid/%;/}
  #echo $rowid
  # build array of rowids for sql query
  if [ -z "$episodearray" ]
  then
    episodearray=$rowid
  else 
    episodearray="$episodearray,$rowid"
  fi
done < <(sqldiff --table EpisodeList $tempdb $comparisondb)

# Build array of changed series
while read -r series ; do
  # find rowids of changes
  seriesid=${series##*=}
  seriesid=${seriesid/%;/}
  # echo $seriesid
  # build array of seriesids for sql query
  if [ -z "$seriesarray" ]
  then
    seriesarray=$seriesid
  else
    seriesarray="$seriesarray,$seriesid"
  fi
done < <(sqldiff --table SeriesStatus $tempdb $comparisondb)

# if episode changes found, output current and previous information
if [ -n "$episodearray" ]
then
  echo -e "\n*** Previous Episode Information ***"
  sqlite3 -column -header $comparisondb "select * from EpisodeList WHERE rowid IN ($episodearray);"
  echo ""
  echo "*** Current Episode Information ***"
  sqlite3 -column -header $tempdb "select * from EpisodeList WHERE rowid IN ($episodearray);"
fi

# if series changes found, output current and previous information
if [ -n "$seriesarray" ]
then
  echo -e "\n*** Previous Series Information ***"
  sqlite3 -column -header $comparisondb "select * from SeriesStatus WHERE rowid IN ($seriesarray);"
  echo ""
  echo "*** Current Series Information ***"
  sqlite3 -column -header $tempdb "select * from SeriesStatus WHERE rowid IN ($seriesarray);"
fi

# Replace current sonarr consolidated db with exported temp one.
mv  $tempdb $comparisondb

exit 0
