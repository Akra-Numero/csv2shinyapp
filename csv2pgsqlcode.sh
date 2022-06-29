#!/usr/bin/bash

## csv2pgsqlcode.sh
## Create PostgreSQL schema files from data in CSV format
## Bijoy Joseph
## 2008.05.20
## Updated: 2020.09.30 (-ve numbers as int)
## Updated: 2011.07.06 (removed Nordic chars from variable names)
## Updated: 2011.06.06 (Float data type processing)
## Updated: 2011.05.27 - Decimal number processing added
## Updated: 2010.08.20
## Usage: $0  CSVFILE SQL_OUTPUT_FILE
#+  e.g.: $0 /home/newdata.csv SQLFILE.sql


## Unique variables for temporary use
UNIQVAL=$RANDOM
TIMED=$(date '+%Y%m%d')

## Check for ARGV and if ARGV[0] (directory) exists
#: ${2?"Usage: $0 CSVFILE OUTPUT_FILE"}  ## Parameter substitution on error
  if test $# -ne 2; then
    echo "Usage: $0  CSVFILE SQL_OUTPUT_FILE"
    echo -e " e.g.: $0 /home/newdata.csv SQLFILE.sql \n"
    exit 1;
  fi

  [ -s "$1" ] || echo "*** ERROR: Source CSV file does not exist - $1 . . ."
  [ -s "$1" ] || exit 1

## signal processing code
  trap "rm -f sqlmake?_*.tmp; exit" SIGHUP SIGINT SIGTERM
  rm -f sqlmake?_$TIMED.tmp
  if [ -s "$2" ]; then
    mv "$2" "$2.old" && rm -f "$2"
  fi

  echo -e "\nCreating SQL DDL file for: $1\n"

## Determine number of variables, and the delimiter
#  NUMVARS=$(head -n1 "$1" | sed -e 's/[,;]/ /g' | wc -w)
  DELIM=$(head -n1 "$1" | sed -e 's/[-a-zA-Z0-9 _%=+\*\$\#\@\!)({}\?\&\."]//g;s%[\[/\]%%g' | sed -e 's/\]//g' | cut -b1)
  NUMVARS=$(head -n1 "$1" | sed -e 's/[- _%=+\*\$\#\@\!)({}\?\&]/_/g;s%[\[/\]%%g' \
     | sed -e 's/\]//g' | sed -e "s/$DELIM/ /g" | wc -w)

  echo "  -> Delimiter= $DELIM, Number of variables=$NUMVARS"
  CHARVARLEN=
  varlength=0

  echo '  -> Processing CHAR and FLOAT variables ...'
#  for LISTNUM in $(seq 1 $NUMVARS)
 seq 1 $NUMVARS | while read LISTNUM
    do
      VARNAME=$(head -n1 "$1" | cut -f $LISTNUM -d "$DELIM" | tr '[A-Z]' '[a-z]' | sed -e 's/ /_/g')
      sed -n '1!p' "$1" | cut -f $LISTNUM -d "$DELIM" | sed -e 's/\ /0/g' >> sqlmake0_${TIMED}.tmp
      CHARVAR=$(sed -e 's/[-.0-9]//g' sqlmake0_${TIMED}.tmp | sort -u | sed -e '/^$/d')

      FLOATVAR=
      INTEGERVAR=
      if [ -z "$CHARVAR" ]; then
        [[ `sed -e 's/[-0-9]*//g' sqlmake0_${TIMED}.tmp | sort -u | sed -e '/^$/d'` == '.' ]] && FLOATVAR=TRUE
        [ -z "$FLOATVAR" ] && INTEGERVAR=TRUE

## Cycle through character variables
      elif [ -n "$CHARVAR" ]; then
        for varnum in $(cat sqlmake0_${TIMED}.tmp | sed -e 's/"//g')
          do
            [ $varlength -lt ${#varnum} ] && varlength=${#varnum}
          done
      fi

      CHARVARLEN=$varlength    ## Length of character variables

## Create output with Variable name and data type, if possible
      printf "    -- $VARNAME -> "
      echo "Charvar length = $CHARVARLEN, Integer = $INTEGERVAR, Float = $FLOATVAR"
      if test $CHARVARLEN -gt 0; then
        echo "    ,${VARNAME//\./_} VARCHAR($CHARVARLEN)" >> sqlmake1_$TIMED.tmp
      elif test $INTEGERVAR; then
        echo "    ,${VARNAME//\./_} INTEGER" >> sqlmake1_$TIMED.tmp
      elif test $FLOATVAR; then
        echo "    ,${VARNAME//\./_} DOUBLE PRECISION" >> sqlmake1_$TIMED.tmp
      fi

      unset CHARVARLEN CHARVAR INTEGERVAR FLOATVAR
      rm -f sqlmake0_${TIMED}.tmp
   done
   echo -e '  ... done!\n'

## Get the DB table name from the filename
#  DBTABLE=${1/\.*}
  DBTABLE=$(basename $1 | tr '[A-Z]' '[a-z]' | cut -f1 -d '.')

## Write output to the specified output file ($2)
#+ -- write table info derived from the CSV file header.
  printf "Creating \COPY file for data from $1"
  { echo "-- File: $2"
    echo "-- Date: "`date '+%Y.%m.%d'`
    echo "-- Author: $USER"
    echo -e '-- Summary: PostgreSQL DDL file to create tables and do data entry \n'
    echo -e '--  SET search_path to public;\n'
    echo "-- Create table $DBTABLE"
    echo "  DROP table IF EXISTS $DBTABLE;"
    echo "  CREATE table $DBTABLE ("
    echo "    ${DBTABLE}_id SERIAL PRIMARY KEY"
  } > "$2"

## Change made on 2011.07.06
#  [ -s  sqlmake1_$TIMED.tmp ] && cat  sqlmake1_$TIMED.tmp | sed -e 's/"//g' >> "$2"
  [ -s  sqlmake1_$TIMED.tmp ] && cat  sqlmake1_$TIMED.tmp | sed -e 's/"//g;s/[äÅ]/a/g;s/ö/o/g;s/-/_/g' >> "$2"

  { echo '  ) -- WITH (OIDS=TRUE)'
    echo -e "  ;\n--  ALTER TABLE $DBTABLE OWNER TO db_user;"
    echo -e '\n-- CREATE indices'
    echo '-- CREATE triggers'
    echo '-- CREATE constraints'
    echo '-- SET client_encoding TO LATIN9; -- ISO885915 (North European)'

    echo -e '\n-- COPY/Load the data to the table using the pgsql COPY command'
    echo '-- NOTE! The file must reside on the server. Otherwise, use \COPY!'

## Change made on 2011.07.06
#    echo "\COPY $DBTABLE `sed -n '1p' "$1" | sed -e 's/ /_/g;s/"//g;s/\./_/g' | sed -e "s/\(.*\)/(\n      \1\n      )/;s/$DELIM/,/g" | tr '[A-Z]' '[a-z]'` "
    echo "\COPY $DBTABLE `sed -n '1p' "$1" | sed -e 's/ /_/g;s/"//g;s/\./_/g' | sed -e 's/[äÅ]/a/g;s/ö/o/g;s/-/_/g' | sed -e "s/\(.*\)/(\n      \1\n      )/;s/$DELIM/,/g" | tr '[A-Z]' '[a-z]'` "
    echo "    FROM '$1' WITH DELIMITER AS '$DELIM' NULL AS ' ' CSV HEADER QUOTE AS '\"'"
  } >> "$2"

## Lines removed from after 'HEADER'
#          FORCE NOT NULL
#            `sed -n '1p' "$1" | sed -e 's/ /_/g;s/"//g' | sed -e "s/$DELIM/\n            ,/g" | tr '[A-Z]' '[a-z]'`

## Remove all temporary files
  rm -f sqlmake?_$TIMED.tmp

  echo -e '  ... done!\n'
