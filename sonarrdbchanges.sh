#!/bin/bash
# This script will show changes in the sonarr database. Tested with v2. Should work with v3

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

# Expand homepath to avoid variables. sqlite commands and cron can have issue with it
eval homedir=~



# Find the sonarr db
sonarrdbpath=`find / -type f \( -name "sonarr.db" -o -name "nzbdrone.db" \) -printf '%T+ %p\n'  2>/dev/null | grep -iv "find:/radarr" | sort -r | head -1 | cut -d' ' -f2-`
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
comparisondb="$homedir/.sonarrepisodeinfo.db"
if [[ ! -r "$comparisondb" ]]
then
  # no comparison needed, create the new db and exit
  sqlite3 $comparisondb "ATTACH DATABASE '$sonarrdbpath' AS 'nzbdrone';CREATE TABLE EpisodeList (Id INTEGER, SeriesID INTEGER,Season INTEGER,Episode INTEGER,Title TEXT,Airdate TEXT);CREATE TABLE SeriesStatus (SeriesID INTEGER, Showname TEXT,Ended INTEGER);INSERT INTO EpisodeList SELECT Id,SeriesID,SeasonNumber,EpisodeNumber,Title,Airdate FROM nzbdrone.Episodes;INSERT INTO SeriesStatus SELECT Id,Title,Status FROM nzbdrone.Series;"
  echo "Comparison DB created. Rerun script after Sonarr has changed."
  exit 0
fi


# Create backups for debugging
today=`date --date=today +%Y-%m-%d`
cp $comparisondb "$homedir/nzbdonebackup/sonarrepisodeinfo-$today.db"
cp $sonarrdbpath "$homedir/nzbdonebackup/sonarrdb-$today.db"

# Create smaller database of current data to compare
tempdb="$homedir/.sonarrtemp.db"

# new create smllaer db of current data
sqlite3 $tempdb "ATTACH DATABASE '$sonarrdbpath' AS 'nzbdrone';CREATE TABLE EpisodeList (Id INTEGER, SeriesID INTEGER,Season INTEGER,Episode INTEGER,Title TEXT,Airdate TEXT);CREATE TABLE SeriesStatus (SeriesID INTEGER, Showname TEXT,Ended INTEGER);INSERT INTO EpisodeList SELECT Id,SeriesID,SeasonNumber,EpisodeNumber,Title,Airdate FROM nzbdrone.Episodes;INSERT INTO SeriesStatus SELECT Id,Title,Status FROM nzbdrone.Series;"


# Changes from previous db to current db
episodedbdiffs=`sqldiff --table EpisodeList $comparisondb $tempdb`
seriesdbdiffs=`sqldiff --table SeriesStatus $comparisondb $tempdb`

# detect episode changes
while read -r line ; do
  # Detect action type and retrieve rowid
  action=${line%% *}
  case $action in
    "") continue;;
    DELETE)
      rowid=${line##*=}
      rowid=${rowid/%;/}
      # build array of rowids for deleted items
      if [ -z "$deletedarray" ]
      then
        deletedarray=$rowid
      else
        deletedarray="$deletedarray,$rowid"
      fi
    ;;
    UPDATE)
      rowid=${line##*=}
      rowid=${rowid/%;/}
      # build array of rowids for updated items
      if [ -z "$updatedarray" ]
      then
        updatedarray=$rowid
      else
        updatedarray="$updatedarray,$rowid"
      fi
    ;;
    INSERT)
      rowid=${line##*VALUES(}
      rowid=${rowid%%,*}
      # build array of rowids for new items
      if [ -z "$newarray" ]
      then
        newarray=$rowid
      else
        newarray="$newarray,$rowid"
      fi
    ;;
    *)
      echo "Unable to process action: $action"
      continue
    ;;
  esac
done <<<$episodedbdiffs



# if episode deletions found, display information
if [ -n "$deletedarray" ]
then
  echo -e "\n*** Deleted Episodes ***"
  sqlite3 -column -header $comparisondb "SELECT B.Showname As Show, A.Season, A.Episode, A.title,A.Airdate FROM EpisodeList A LEFT JOIN SeriesStatus B ON A.SeriesID = B.SeriesID WHERE A.rowid IN ($deletedarray) ORDER By Show,A.Season,A.Episode;"
  episodechanges=1
fi

# if new episodes found, display information
if [ -n "$newarray" ]
then
  echo -e "\n*** New Episodes ***"
  sqlite3 -column -header $tempdb "SELECT B.Showname As Show, A.Season, A.Episode, A.title, A.Airdate FROM EpisodeList A LEFT JOIN SeriesStatus B ON A.SeriesID = B.SeriesID WHERE A.rowid IN ($newarray) ORDER By Show,A.Season,A.Episode;"
  episodechanges=1
fi

# if episode changes found, output current and previous information
if [ -n "$updatedarray" ]
then
  echo -e "\n*** Previous Episode Information ***"
  sqlite3 -column -header $comparisondb "SELECT B.Showname As Show, A.Season, A.Episode, A.title, A.airdate FROM EpisodeList A LEFT JOIN SeriesStatus B ON A.SeriesID = B.SeriesID WHERE A.rowid IN ($updatedarray) ORDER By Show,A.Season,A.Episode;"
  echo ""
  echo "*** Current Episode Information ***"
  sqlite3 -column -header $tempdb "SELECT B.Showname As Show, A.Season, A.Episode, A.title, A.airdate FROM EpisodeList A LEFT JOIN SeriesStatus B ON A.SeriesID = B.SeriesID WHERE A.rowid IN ($updatedarray) ORDER By Show,A.Season,A.Episode;"
  episodechanges=1
fi


# Detect series changes
while read -r series ; do
  # Detect action type and retrieve seriesid
  saction=${series%% *}
  case $saction in
    "") continue;;
    DELETE)
      seriesid=${series##*=}
      seriesid=${seriesid/%;/}
      # build array of seriesids for deleted items
      if [ -z "$deletedseriesarray" ]
      then
        deletedseriesarray=$seriesid
      else
        deletedseriesarray="$deletedseriesarray,$seriesid"
      fi
    ;;
    UPDATE)
      seriesid=${series##*=}
      seriesid=${seriesid/%;/}
      # build array of seriesids for updated items
      if [ -z "$updatedseriesarray" ]
      then
        updatedseriesarray=$seriesid
      else
        updatedseriesarray="$updatedseriesarray,$seriesid"
      fi
    ;;
    INSERT)
      seriesid=${series##*VALUES(}
      seriesid=${seriesid%%,*}
      # build array of seriesids for new items
      if [ -z "$newseriesarray" ]
      then
        newseriesarray=$seriesid
      else
        newseriesarray="$newseriesarray,$seriesid"
      fi
    ;;
    *)
      echo "Unable to process action: $saction"
      continue
    ;;
  esac
done <<<$seriesdbdiffs

# if series deletions found, display information
if [ -n "$deletedseriesarray" ]
then
  echo -e "\n*** Deleted Series ***"
  sqlite3 -column -header $comparisondb "select Showname, CASE Ended WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' END Status from SeriesStatus WHERE rowid IN ($deletedseriesarray);"
  serieschanges=1
fi

# if new series found, display information
if [ -n "$newseriesarray" ]
then
  echo -e "\n*** New Series ***"
  sqlite3 -column -header $tempdb "select Showname, CASE Ended WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' END Status from SeriesStatus WHERE rowid IN ($newseriesarray);"
  serieschanges=1
fi

# if series state changes found, output current and previous information
if [ -n "$updatedseriesarray" ]
then
  echo -e "\n*** Previous State  ***"
  sqlite3 -column -header $comparisondb "select Showname, CASE Ended WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' END Status from SeriesStatus WHERE rowid IN ($updatedseriesarray);"
  echo ""
  echo "*** Current State ***"
  sqlite3 -column -header $tempdb "select Showname, CASE Ended WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' END Status from SeriesStatus WHERE rowid IN ($updatedseriesarray);"
  serieschanges=1
fi


if [ -n "$episodechanges" ] || [ -n "$serieschanges" ]
then
  # Replace current sonarr consolidated db with exported temp one.
  mv  $tempdb $comparisondb
else
  echo "no changes"
  rm $tempdb
fi

exit 0
