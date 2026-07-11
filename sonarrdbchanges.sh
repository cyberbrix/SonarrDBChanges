#!/bin/bash
# This script will show changes in the sonarr database. Works with v4
# Supply the path to the db as the first/only argument
# eg - <path to script>/sonarrdbchanges/sonarrdbchanges_v3.sh "/docker/sonarr/data/sonarr.db"
# v3.0


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

# Sets the file path. If it doesn't exist, search for it. The is the current Sonarr state
sonarrdbpath="$1"
#sonarrdbpath="/var/lib/sonarr/sonarr.db"

if [ ! -f "$sonarrdbpath" ]
then
  echo "File doees not exist. Searching for one."
  # Find the sonarr db
  sonarrdbpath=$(find / -type f \( -name "sonarr.db" -o -name "nzbdrone.db" \) -printf '%T+ %p\n'  2>/dev/null | grep -iv "find:/radarr" | sort -r | head -1 | cut -d' ' -f2-)
  echo "Search complete."
fi

if [[ ! -r "$sonarrdbpath" ]]
then
  echo -e "\nnzbdone.db is not found or accessible"
  exit 1
fi

echo "Sonarr DB path: $sonarrdbpath"


# Test if db tables are accessible
sonarrtables=$(sqlite3 "$sonarrdbpath" ".tables")
if [[ $sonarrtables != *"Episodes"* ]] || [[ $sonarrtables != *"Series"* ]]
then
  echo -e "\nThe needed tables were not found (Episodes and Series). $sonarrdbpath may not be the right database"
  exit 1
fi 

# Check of  comparison db for reference - This is the previous Sonarr state
comparisondb="$homedir/.sonarrepisodeinfo.db"
#comparisondb="/mnt/nasscripts/sonarrdbchanges/comparison_test.db" # for testing purposes
#comparisondb="$homedir/comparison_test.db"
if [[ ! -r "$comparisondb" ]]
then
  # no comparison needed, create the new db and exit.  This table uses the tvdbid id from the series table to help identify each episode
sqlite3 "$comparisondb" "ATTACH DATABASE '$sonarrdbpath' AS 'nzbdrone'; CREATE TABLE Series As SELECT TvdbId,Title,Status FROM nzbdrone.Series; CREATE TABLE Episodes AS SELECT s.TvdbId,e.SeasonNumber,e.EpisodeNumber,e.Title,e.AirDate FROM nzbdrone.Episodes e JOIN nzbdrone.Series s ON s.Id = e.SeriesId;"


  if [ $? -ne 0 ]
  then
    echo "ERROR: SQLite table creation failed"2
    exit 1
  fi
  echo "Comparison DB created. Rerun script after Sonarr has changed."
   exit 0
fi


# Create smaller database of current data to compare
tempdb=$(mktemp -u --suffix=.db "$homedir/sonarr_tmp.XXXXXX")

# new create smaller db of current data - This table uses the tvdbid id from the series table to help identify each episode
sqlite3 "$tempdb" "ATTACH DATABASE '$sonarrdbpath' AS 'nzbdrone'; CREATE TABLE Series As SELECT TvdbId,Title,Status FROM nzbdrone.Series; CREATE TABLE Episodes AS SELECT s.TvdbId,e.SeasonNumber,e.EpisodeNumber,e.Title,e.AirDate FROM nzbdrone.Episodes e JOIN nzbdrone.Series s ON s.Id = e.SeriesId;"

# create arrays used for data processing
#newseriesarray=() # series which have been created - rowid, not seriesid
#deletedseriesarray=() # series which have been deleted
#updatedseriesarray=() # series which have been updated
#updatedseriestitlearray=() # series which have been updated
#deletedepisodearray=() # array for deleted episodes
#DeletedEpisodeRowIDArray=() # array for deleted episodes
#updatedepisodearray=() # array for updated episodes
#NewEpisodeArray=() # array for new episodes
#NewSeriesIDArray=() # array for new series, by Series ID
#updatedmaybedeletedarray=() # array for updated episodes which may be deleted
#updatedseriesmaybedeletedarray=() # array for updated episodes which may be deleted
#PreviousSeriesMayBeDeletedRowIDArray=() # Row IDs of previous (comparison)
#DeletedSeriesRowIDArray=() # RowID of previous series which are deleted

#declare -A NewSeriesID_Array # seriesID for newly added series


# if new series found, display information - UPDATED
NewSeriesAdded=$(sqlite3 -column -header "$tempdb" "ATTACH DATABASE '$comparisondb' AS prev; SELECT c.Title AS Showname, CASE c.Status WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' WHEN '2' THEN 'Upcoming' WHEN '-1' THEN 'Deleted' END Status FROM Series c LEFT JOIN prev.Series p ON p.TvdbId = c.TvdbId WHERE p.TvdbId IS NULL ORDER By c.Title COLLATE NOCASE;")
if [[ -n $NewSeriesAdded ]]
then
  echo -e "\n*** New Series ***"
  echo "$NewSeriesAdded"
  sonarrdbchanges=1
fi

# if existing series deleted, display information - UPDATED
ExistingSeriesDeleted=$(sqlite3 -column -header "$tempdb" "ATTACH DATABASE '$comparisondb' AS prev; SELECT p.Title AS Showname, CASE p.Status WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' WHEN '2' THEN 'Upcoming' WHEN '-1' THEN 'Deleted' END Status FROM prev.Series p LEFT JOIN Series c ON c.TvdbId = p.TvdbId WHERE c.TvdbId IS NULL ORDER By p.Title COLLATE NOCASE;")
if [[ -n $ExistingSeriesDeleted ]]
then
  echo -e "\n*** Deleted Series ***"
  echo "$ExistingSeriesDeleted"
  sonarrdbchanges=1
fi


# if series title has changed - UPDATED
SeriesTitleChanged=$(sqlite3 -column -header "$tempdb" "ATTACH DATABASE '$comparisondb' AS prev; SELECT p.Title  AS 'Prevous Showname', c.Title  AS 'Current Showname' FROM Series c JOIN prev.Series p ON p.TvdbId = c.TvdbId WHERE IFNULL(p.Title,'') != IFNULL(c.Title,'') ORDER By p.Title COLLATE NOCASE ;")
if [[ -n $SeriesTitleChanged ]]
then
  echo -e "\n*** Series Name Changes ***"
  echo "$SeriesTitleChanged"
  sonarrdbchanges=1
fi


# if series state has changed - UPDATED
SeriesStateChanged=$(sqlite3 -column -header "$tempdb" "ATTACH DATABASE '$comparisondb' AS prev; SELECT c.Title AS Showname,CASE p.Status WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' WHEN '2' THEN 'Upcoming' WHEN '-1' THEN 'Deleted' END 'Previous Status', CASE c.Status WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' WHEN '2' THEN 'Upcoming' WHEN '-1' THEN 'Deleted' END 'Current Status' FROM Series c JOIN prev.Series p ON p.TvdbId = c.TvdbId WHERE IFNULL(p.Status,'') != IFNULL(c.Status,'') ORDER By p.Title COLLATE NOCASE;")
if [[ -n $SeriesStateChanged ]]
then
  echo -e "\n*** Series Status Changes ***"
  echo "$SeriesStateChanged"
  sonarrdbchanges=1
fi

# if new episodes found for existing series. Not adding new episodes for new series - UPDATED
NewEpisodesExistingShows=$(sqlite3 -column -header "$tempdb" "ATTACH DATABASE '$comparisondb' AS prev; SELECT s.Title AS Showname, printf('S%02dE%02d', e.SeasonNumber, e.EpisodeNumber) AS Episode,e.Title,e.AirDate FROM Episodes e
JOIN Series s ON s.TvdbId = e.TvdbId
WHERE EXISTS (
    SELECT 1
    FROM prev.Series p
    WHERE p.TvdbId = e.TvdbId
) AND NOT EXISTS (
    SELECT 1
    FROM prev.Episodes pe
    WHERE pe.TvdbId = e.TvdbId
      AND pe.SeasonNumber = e.SeasonNumber
      AND pe.EpisodeNumber = e.EpisodeNumber
) ORDER By s.Title COLLATE NOCASE,e.SeasonNumber,e.EpisodeNumber;")

if [[ -n $SeriesStateChanged ]]
then
  echo -e "\n*** New Episodes ***"
  echo "$NewEpisodesExistingShows"
  sonarrdbchanges=1
fi

# if new episodes deleted existing series. Not removing episodes for existing series - UPDATED
ExistingShowsEpisodesDeleted=$(sqlite3 -column -header "$tempdb" "ATTACH DATABASE '$comparisondb' AS prev; SELECT ps.Title AS Showname, printf('S%02dE%02d', pe.SeasonNumber, pe.EpisodeNumber) AS Episode, pe.Title, pe.AirDate
FROM prev.Episodes pe
JOIN prev.Series ps
    ON ps.TvdbId = pe.TvdbId
WHERE EXISTS (
    SELECT 1
    FROM Series s
    WHERE s.TvdbId = pe.TvdbId
) AND NOT EXISTS (
    SELECT 1
    FROM Episodes e
    WHERE e.TvdbId = pe.TvdbId
      AND e.SeasonNumber = pe.SeasonNumber
      AND e.EpisodeNumber = pe.EpisodeNumber
) ORDER By ps.Title COLLATE NOCASE,pe.SeasonNumber,pe.EpisodeNumber;")

if [[ -n $ExistingShowsEpisodesDeleted ]]
then
  echo -e "\n*** Deleted Episodes ***"
  echo "$ExistingShowsEpisodesDeleted"
  sonarrdbchanges=1
fi


# Changes in episode title or airdate - UPDATED
ExistingEpisodeChanges=$(sqlite3 -line -list "$tempdb" "ATTACH DATABASE '$comparisondb' AS prev;
SELECT
    s.Title AS ShowName,
    printf('%02d', e.SeasonNumber) AS SeasonNumber,
    printf('%02d', e.EpisodeNumber) AS EpisodeNumber,

    pe.Title    AS OldTitle,
    e.Title     AS NewTitle,

    pe.AirDate  AS OldAirDate,
    e.AirDate   AS NewAirDate

FROM Episodes e
JOIN Series s
    ON s.TvdbId = e.TvdbId
JOIN prev.Episodes pe
    ON pe.TvdbId        = e.TvdbId
   AND pe.SeasonNumber  = e.SeasonNumber
   AND pe.EpisodeNumber = e.EpisodeNumber

WHERE
       IFNULL(pe.Title,'')   <> IFNULL(e.Title,'')
    OR IFNULL(pe.AirDate,'') <> IFNULL(e.AirDate,'') ORDER BY s.Title COLLATE NOCASE,e.SeasonNumber,e.EpisodeNumber;")


if [[ -n $ExistingEpisodeChanges ]]
then

  while IFS='|' read -r showname showseason showepisode showoldtitle shownewtitle showoldairdate shownewairdate
  do

    echo ""
    # checks if previously processed show is the same. skips the show name if so
    if [[ "$previousshowname" != "$showname" ]]
    then
      echo ""
      echo "======================"
      echo "$showname"
     echo "--------------"
    fi

    echo "S:$showseason E:$showepisode"

    # Checks if the episode title has changed
    [[ "$showoldtitle" != "$shownewtitle" ]] && echo "Title: $showoldtitle => $shownewtitle"

    # checks if the airdate has changed
    [[ "$showoldairdate" != "$shownewairdate" ]] && echo "Airdate: $showoldairdate => $shownewairdate"

    # sets current show name as previous
    previousshowname=$showname

  done < <(echo "$ExistingEpisodeChanges")
  sonarrdbchanges=1
fi
 

# If there are changes, replace the comparison file for the next run
if [[ -n "$sonarrdbchanges" ]]
then
  # Replace current sonarr consolidated db with exported temp one.
  mv  "$tempdb" "$comparisondb"
  
else
  echo "no changes"
  rm "$tempdb"
fi

exit 0
