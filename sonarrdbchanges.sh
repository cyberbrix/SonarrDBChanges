#!/bin/bash
# This script will show changes in the sonarr database. Works with v3
# v 1.4.1

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

# Sets the file path. If it doesn't exist, search for it
sonarrdbpath="/var/lib/sonarr/sonarr.db"

if [ ! -f "$sonarrdbpath" ]
then
  echo "File doees not exist"
  # Find the sonarr db
  sonarrdbpath=$(find / -type f \( -name "sonarr.db" -o -name "nzbdrone.db" \) -printf '%T+ %p\n'  2>/dev/null | grep -iv "find:/radarr" | sort -r | head -1 | cut -d' ' -f2-)
fi

if [[ ! -r "$sonarrdbpath" ]]
then
  echo -e "\nnzbdone.db is not found or accessible"
  exit 1
fi

echo "Sonarr DB path: $sonarrdbpath"

# Test if db tables are accessable
sonarrtables=$(sqlite3 "$sonarrdbpath" ".tables")
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
  sqlite3 "$comparisondb" "ATTACH DATABASE '$sonarrdbpath' AS 'nzbdrone';CREATE TABLE EpisodeList (Id INTEGER, SeriesID INTEGER,Season INTEGER,Episode INTEGER,Title TEXT,Airdate TEXT);CREATE TABLE SeriesStatus (SeriesID INTEGER, Showname TEXT,Ended INTEGER);INSERT INTO EpisodeList SELECT Id,SeriesID,SeasonNumber,EpisodeNumber,Title,Airdate FROM nzbdrone.Episodes;INSERT INTO SeriesStatus SELECT Id,Title,Status FROM nzbdrone.Series;"
  echo "Comparison DB created. Rerun script after Sonarr has changed."
  exit 0
fi


# Create smaller database of current data to compare
tempdb="$homedir/.sonarrtemp.db"

# new create smaller db of current data
sqlite3 "$tempdb" "ATTACH DATABASE '$sonarrdbpath' AS 'nzbdrone';CREATE TABLE EpisodeList (Id INTEGER, SeriesID INTEGER,Season INTEGER,Episode INTEGER,Title TEXT,Airdate TEXT);CREATE TABLE SeriesStatus (SeriesID INTEGER, Showname TEXT,Ended INTEGER);INSERT INTO EpisodeList SELECT Id,SeriesID,SeasonNumber,EpisodeNumber,Title,Airdate FROM nzbdrone.Episodes;INSERT INTO SeriesStatus SELECT Id,Title,Status FROM nzbdrone.Series;"

# create arrays used for data processing
newseriesidarray=() # seriesID for newly added series
newseriesarray=() # series which have been created - rowid, not seriesid
deletedseriesarray=() # series which have been deleted
updatedseriesarray=() # series which have been updated
updatedseriestitlearray=() # series which have been updated
deletedepisodearray=() # array for deleted episodes
updatedepisodearray=() # array for updated episodes
newepisodearray=() # array for new episodes
updatedmaybedeletedarray=() # array for updated episodes which may be deleted
updatedseriesmaybedeletedarray=() # array for updated episodes which may be deleted

# Detect series changes - skipping entire line rewrite
while read -r series
do
  # Detect action type and retrieve seriesid
  saction=${series%% *}
  case $saction in
    "") continue;;
    DELETE)
      seriesid=${series##*=}
      seriesid=${seriesid/%;/}
      # build array of seriesids for deleted items
      #deletedseriesarray+=($seriesid)
      updatedseriesmaybedeletedarray+=($seriesid)
    ;;
    UPDATE)
      seriesid=${series##*=}
      seriesid=${seriesid/%;/}
      if  echo "$series" | grep -iq "SET Showname"
      then
        updatedseriestitlearray+=($seriesid)
        continue
      else
        updatedseriesarray+=($seriesid)
        continue
      fi
    ;;
    INSERT)
      seriesid=${series##*VALUES(}
      seriesidnum=$(echo $seriesid | cut -d',' -f2)
      seriesrowid=$(echo $seriesid | cut -d',' -f1)
      newseriesarray+=($seriesrowid)
      newseriesidarray+=($seriesidnum)
    ;;
    *)
      echo "Unable to process series action: $saction"
      continue
    ;;
  esac
done < <(sqldiff --table SeriesStatus "$comparisondb" "$tempdb" | grep -iv "UPDATE SeriesStatus SET SeriesID")

# List of series ids which already exist, just a different row
existingseriesids=$(sqlite3 "$comparisondb" "select SeriesID FROM SeriesStatus;")

# find series which don't currently exist but replacing an existing db entry
while read -r updateseries
do
  # detect the id of the episode
  updateseriestrimmedprefix=${updateseries#*SET SeriesID=}
  updateseriesid=${updateseriestrimmedprefix%%,*}
  seriesid=${updateseriestrimmedprefix##*=}
  seriesid=${seriesid/%;/}

  updatedseriesmaybedeletedarray+=($seriesid)

  # Check if it is in the current list of episodes. If not, it is new
  if [[ $existingseriesids =~ [[:space:]]$updateseriesid[[:space:]] ]]
  then
    : # take no actions
  else
    newepisodearray+=($seriesid)
  fi
done < <(sqldiff --table SeriesStatus "$comparisondb" "$tempdb" | grep -i "^UPDATE SeriesStatus SET SeriesID")

if [[ $updatedseriesmaybedeletedarray != '' ]]
then
  updatedseriesmaybedeletedarray=$(echo ${updatedseriesmaybedeletedarray[@]} | sed 's/ /,/g')
  while read -r seriestocheck
  do
    # Parse current rowid, episodeid
    currentrowid=$(echo "$seriestocheck" | cut -d'|' -f1)
    seriesidtocheck=$(echo "$seriestocheck" | cut -d'|' -f2)

    # check for the episode in the new db. if it exists, do nothing, if it
    if [[ $(sqlite3 "$tempdb" "SELECT EXISTS(SELECT * FROM SeriesStatus WHERE SeriesID=$seriesidtocheck);") -eq 1 ]]
    then
      continue
    fi

    deletedseriesarray+=($currentrowid)
  done < <(sqlite3 "$comparisondb" "SELECT rowid,SeriesID From SeriesStatus WHERE rowid IN ($updatedseriesmaybedeletedarray);")
fi

# detect episodes changes
while read -r line 
do
  # Detect action type and retrieve rowid
  action=${line%% *}
  case $action in
    "") continue;;
    DELETE)
      rowid=${line##*=}
      rowid=${rowid/%;/}
      # build array of rowids for deleted items
      deletedepisodearray+=($rowid)
    ;;
    UPDATE)
      rowid=${line##*=}
      rowid=${rowid/%;/}
      # build array of rowids for updated items
      updatedepisodearray+=($rowid)
    ;;
    INSERT)
      rowid=${line##*VALUES(}
      episodeseriesid=$(echo "$rowid" | cut -d',' -f3)
      rowid=${rowid%%,*}
      for epnum in "${newseriesidarray[@]}"
      do
        if [[ "$episodeseriesid" == "$epnum" ]] 
        then
          continue 2
        fi
      done
      
      # build array of rowids for new items
      newepisodearray+=($rowid)
    ;;
    *)
      echo "Unable to process episode action: $action"
      continue
    ;;
  esac
done < <(sqldiff --table EpisodeList "$comparisondb" "$tempdb" | grep -iv "^UPDATE EpisodeList SET Id")

# List of episode id which already exist, just a different row
existingepisodeids=$(sqlite3 "$comparisondb" "select id FROM EpisodeList;")

# find episodes which don't current exist but replacing an existing db entry
while read -r updateline
do
  # detect the id of the episode
  updatelinetrimmedprefix=${updateline#*SET Id=}
  updatelineid=${updatelinetrimmedprefix%%,*}
  rowid=${updateline##*=}
  rowid=${rowid/%;/}
  
  # if update line is replacing a full show, build an array to check if the replaced show is deleted or moved
  if  echo "$updatelinetrimmedprefix" | grep -iq "SeriesID"
  then
    updatedmaybedeletedarray+=($rowid)
  fi
   
  # Check if it is in the current list of episodes. If not, it is new
  if [[ $existingepisodeids =~ [[:space:]]$updatelineid([[:space:]]|$) ]]
  then
    : # take no actions
  else
    newepisodearray+=($rowid)
  fi
done < <(sqldiff --table EpisodeList "$comparisondb" "$tempdb" | grep -i "^UPDATE EpisodeList SET Id")


if [[ $updatedmaybedeletedarray != '' ]]
then
  updatedmaybedeletedarray=$(echo ${updatedmaybedeletedarray[@]} | sed 's/ /,/g')
  while read -r episodetocheck
  do
    # Parse current rowid, episodeid
    currentrowid=$(echo "$episodetocheck" | cut -d'|' -f1)
    episodeidtocheck=$(echo "$episodetocheck" | cut -d'|' -f2)
    seriesidtocheck=$(echo $episodetocheck | cut -d'|' -f3)
    
    # check for the episode in the new db. if it exists, do nothing, if it 	
    if [[ $(sqlite3 "$tempdb" "SELECT EXISTS(SELECT * FROM EpisodeList WHERE ID=$episodeidtocheck);") -eq 1 ]]
    then
      continue
    fi

    # Don't add episodes for deleted series
    #tmpdeletedseries=${deletedseriesarray[*]}
    tmpdeletedseries=$(echo ${deletedseriesarray[@]} | sed 's/ /,/g')
    if [[ $(sqlite3 "$comparisondb" "SELECT 1 AS value_found WHERE $seriesidtocheck IN ( select SeriesID from SeriesStatus WHERE rowid IN ($tmpdeletedseries));") -eq 1 ]]
    then
      continue
    fi
    
    deletedepisodearray+=($currentrowid)
  done < <(sqlite3 "$comparisondb" "SELECT rowid,id,SeriesID From Episodelist WHERE rowid IN ($updatedmaybedeletedarray);")
fi



# Convert Arrays to comma separated list for sql usage
OIFS=$IFS
IFS=','
deletedepisodearray=${deletedepisodearray[*]}
newepisodearray=${newepisodearray[*]}
updatedepisodearray=${updatedepisodearray[*]}
deletedseriesarray=${deletedseriesarray[*]}
updatedseriesarray=${updatedseriesarray[*]}
newseriesarray=${newseriesarray[*]}
updatedmaybedeletedarray=${updatedmaybedeletedarray[*]}
updatedseriestitlearray=${updatedseriestitlearray[*]}
IFS=$OIFS



# if episode deletions found, display information
if [[ $deletedepisodearray != '' ]]
then  
  echo -e "\n*** Deleted Episodes ***"
  sqlite3 -column -header "$comparisondb" "SELECT B.Showname As Show, A.Season, A.Episode, A.title,A.Airdate FROM EpisodeList A LEFT JOIN SeriesStatus B ON A.SeriesID = B.SeriesID WHERE A.rowid IN ($deletedepisodearray) ORDER By Show,A.Season,A.Episode;"
  episodechanges=1
fi

# if new episodes found, display information
if [[ $newepisodearray != '' ]]
then
  echo -e "\n*** New Episodes ***"
  sqlite3 -column -header "$tempdb" "SELECT B.Showname As Show, A.Season, A.Episode, A.title, A.Airdate FROM EpisodeList A LEFT JOIN SeriesStatus B ON A.SeriesID = B.SeriesID WHERE A.rowid IN ($newepisodearray) ORDER By Show,A.Season,A.Episode;"
  episodechanges=1
fi


# if episode changes found, output current and previous information
if [[ $updatedepisodearray != '' ]]
then
  OIFS=$IFS;
  IFS="|";
  while read -r sqlepisodeinfo
  do
    # create array
    changedepisode=($sqlepisodeinfo);
  
    # check if expected number of tokens
    if [[ ${#changedepisode[@]} -gt 9 ]]
    then 
      echo ""
      echo "Wrong number of items in: $sqlepisodeinfo"
      continue
    fi

    # set tokens as variables for ease of use
    showname=${changedepisode[0]}
    showoldseason=${changedepisode[1]}
    showoldepisode=${changedepisode[2]}
    showoldtitle=${changedepisode[3]}
    showoldairdate=${changedepisode[4]}
    shownewseason=${changedepisode[5]}
    shownewepisode=${changedepisode[6]}
    shownewtitle=${changedepisode[7]}
    shownewairdate=${changedepisode[8]}
   
    echo ""
    # checks if previously processed show is the same. skips the show name if so
    if [[ "$previousshowname" != "$showname" ]]
    then
      echo ""
      echo "======================"
      echo "$showname"
      echo "--------------"
    fi
  
    # Checks if the season or episode changed 
    if [[ "$showoldseason" != "$shownewseason" ]] || [[ "$showoldepisode" != "$shownewepisode" ]]
    then
      echo "S:$showoldseason E:$showoldepisode => S:$shownewseason E:$shownewepisode"
    else
      echo "S:$showoldseason E:$showoldepisode"
    fi
    
    # Checks if the episode title has changed
    [[ "$showoldtitle" != "$shownewtitle" ]] && echo "Title: $showoldtitle => $shownewtitle"
    
    # checks if the airdate has changed
    [[ "$showoldairdate" != "$shownewairdate" ]] && echo "Airdate: $showoldairdate => $shownewairdate"
  
    # sets current show name as previous
    previousshowname=$showname

  done < <(sqlite3 "$comparisondb" "ATTACH DATABASE '$tempdb' AS 'newdata';SELECT B.Showname, A.Season, A.Episode, A.title,A.airdate,C.Season,C.Episode,C.title,C.airdate FROM EpisodeList A LEFT JOIN SeriesStatus B ON A.SeriesID = B.SeriesID JOIN newdata.episodelist C ON A.rowid = C.rowid  WHERE A.rowid IN ($updatedepisodearray) ORDER By B.Showname,A.Season,A.Episode;")
  echo ""
  echo ""
  IFS=$OIFS
  episodechanges=1
fi


# if series deletions found, display information
if [[ $deletedseriesarray != '' ]]
then
  echo -e "\n*** Deleted Series ***"
  sqlite3 -column -header "$comparisondb" "select Showname, CASE Ended WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' WHEN '2' THEN 'Upcoming' WHEN '-1' THEN 'Deleted' END Status from SeriesStatus WHERE rowid IN ($deletedseriesarray);"
  serieschanges=1
fi

# if new series found, display information
if [[ $newseriesarray != '' ]]
then
  echo -e "\n*** New Series ***"
  sqlite3 -column -header "$tempdb" "select Showname, CASE Ended WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' WHEN '2' THEN 'Upcoming' WHEN '-1' THEN 'Deleted' END Status from SeriesStatus WHERE rowid IN ($newseriesarray);"
  serieschanges=1
fi

# if series title has changed
if [[ $updatedseriestitlearray != '' ]]
then
  echo -e "\n*** Series Name Changes ***"
  sqlite3 -header -column "$comparisondb" "ATTACH DATABASE '$tempdb' AS 'newdata'; SELECT A.Showname As 'Prevous Showname',B.showname AS 'Current Showname' from SeriesStatus A LEFT JOIN newdata.SeriesStatus B ON A.SeriesID = B.SeriesID  WHERE A.rowid IN ($updatedseriestitlearray) ORDER By A.Showname;"
  serieschanges=1
fi

# if series state changes found, output current and previous information
if [[ $updatedseriesarray != '' ]]
then
  echo -e "\n*** Series Status Changes ***"
  sqlite3 -header -column "$comparisondb" "ATTACH DATABASE '$tempdb' AS 'newdata'; SELECT B.Showname,CASE A.Ended WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' WHEN '2' THEN 'Upcoming' WHEN '-1' THEN 'Deleted' END 'Previous Status',CASE B.Ended WHEN '0' THEN 'Ongoing' WHEN '1' THEN 'Ended' WHEN '2' THEN 'Upcoming' WHEN '-1' THEN 'Deleted' END 'Current Status' from SeriesStatus A LEFT JOIN newdata.SeriesStatus B ON A.SeriesID = B.SeriesID  WHERE A.rowid IN ($updatedseriesarray) ORDER By A.Showname;"
  serieschanges=1
fi


if [ -n "$episodechanges" ] || [ -n "$serieschanges" ]
then
  # Replace current sonarr consolidated db with exported temp one.
  mv  "$tempdb" "$comparisondb"
else
  echo "no changes"
  rm "$tempdb"
fi

exit 0
