#!/bin/bash
#
# Author:	Pedro Valero
#
# Description: Script to compare zearch with other tools.
#
# Date: 14/01/2019

REPAIR="../../Re-Pair/repair110811/repair"
DESPAIR="../../Re-Pair/repair110811/despair"
GREP="../../grep-3.3/src/grep"
ZEARCH="../zearch"
HYPERSCAN="./hyperscan"
LZ4="../../lz4/lz4"
ZSTD="../../zstd/zstd"
NAVARRO="../../code/search"
LZW="../../code/compress"
GZIP="../../gzip-1.9/gzip"
COUNTER=0

TMP="tmp.txt"
STATS_SCRIPT="./statistics.py"

DE_COMPRESSORS=1

# args: regex for rg, regex for zearch, regex por grep input (compress .rp)
run_simple_case() {
	COUNTER=$((COUNTER+1))
	echo "\"Regex\": \"r$COUNTER\"," >> $JSON

	TIMEOUT="timeout 20"
	RGTO=0
	GTO=0
	LZTO=0
	NTO=0
	HTO=0

	BEGIN=$(date +%s%3N)
	for i in `seq 1 $REPS`; do $ZEARCH -c "$2" $6.rp 2>&1 1>/dev/null; done
	END=$(date +%s%3N)

	MATCHESGG=$(LC_ALL=C $TIMEOUT $GREP -c "$3" $6 2>/dev/null)
	if [[ $? == 124 ]]; then GTO=1; MATCHESGG=0; fi

	MATCHESZ=$($ZEARCH -c "$2" $6.rp 2>/dev/null)

	MATCHESH=$(LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1" 2>/dev/null)
	if [[ $? == 124 ]]; then HTO=1; MATCHESH=0; fi

	MATCHESN=$(LC_ALL=C $TIMEOUT $NAVARRO "$4" $6.Z 2>/dev/null)
	if [[ $? == 124 ]]; then NTO=1; MATCHESN=0; fi

	# ZEARCH
	rm $TMP
	LC_ALL=C $ZEARCH -c "$2" $6.rp
	LC_ALL=C $ZEARCH -c "$2" $6.rp
	LC_ALL=C $ZEARCH -c "$2" $6.rp
	for i in `seq 1 $REPS`; do
		BEGIN=$(date +%s%3N)
		LC_ALL=C $ZEARCH -c "$2" $6.rp
		END=$(date +%s%3N)
		echo $((END-BEGIN)) >> $TMP
		echo $((END-BEGIN)) >> gsearch.txt
	done
	echo "\"zearch\": "`$STATS_SCRIPT $TMP`"," >> $JSON

	# GREP

	if [[ $GTO == 1 ]]; then
		rm $TMP
		for i in `seq 1 $REPS`; do
			echo 20000 >> $TMP
			echo 20000 >> zgrep_lz4.txt
			echo 20000 >> zgrep_zstd.txt
			echo 20000 >> grep.txt
			echo 20000 >> zgrep_lz4_p.txt
			echo 20000 >> zgrep_zstd_p.txt
		done
		echo "\"zgrep_lz4\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zgrep_zstd\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zgrep_gzip\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zgrep_lz4_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zgrep_zstd_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zgrep_gzip_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"grep\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	else
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $GREP -c "$3"
		rm $TMP
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $GREP -c "$3"
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $GREP -c "$3"
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $GREP -c "$3"
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $GREP -c "$3"
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> zgrep_lz4_p.txt
		done
		echo "\"zgrep_lz4_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		LC_ALL=C $GREP -c "$3" "$6"
		rm $TMP
		LC_ALL=C $GREP -c "$3" "$6"
		LC_ALL=C $GREP -c "$3" "$6"
		LC_ALL=C $GREP -c "$3" "$6"
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $GREP -c "$3" "$6"
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> grep.txt
		done
		echo "\"grep\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $GREP -c "$3"
		rm $TMP
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $GREP -c "$3"
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $GREP -c "$3"
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $GREP -c "$3"
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $GREP -c "$3"
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> zgrep_zstd_p.txt
		done
		echo "\"zgrep_zstd_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	fi

	# HYPERSCAN

	if [[ $HTO == 1 ]]; then
		rm $TMP
		for i in `seq 1 $REPS`; do
			echo 20000 >> $TMP
			echo 20000 >> hyperscan.txt
			echo 20000 >> zhs_lz4_p.txt
		done
		echo "\"hyperscan\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zhs_lz4_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	else
		LC_ALL=C $HYPERSCAN "$1" $6
		rm $TMP
		LC_ALL=C $HYPERSCAN "$1" $6
		LC_ALL=C $HYPERSCAN "$1" $6
		LC_ALL=C $HYPERSCAN "$1" $6
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $HYPERSCAN "$1" $6
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> hyperscan.txt
		done
		echo "\"hyperscan\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1"
		rm $TMP
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1"
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1"
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1"
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1"
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> zhs_lz4_p.txt
		done
		echo "\"zhs_lz4_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $HYPERSCAN "$1"
		rm $TMP
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $HYPERSCAN "$1"
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $HYPERSCAN "$1"
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $HYPERSCAN "$1"
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $HYPERSCAN "$1"
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> zhs_zstd_p.txt
		done
		echo "\"zhs_zstd_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	fi

	# NAVARRO

	if [[ $NTO == 1 ]]; then
		rm $TMP
		for i in `seq 1 $REPS`; do
			echo 20000 >> $TMP
			echo 20000 >> navarro.txt
		done
		echo "\"navarro\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	else
		LC_ALL=C $NAVARRO "$4" $6.Z
		rm $TMP
		LC_ALL=C $NAVARRO "$4" $6.Z
		LC_ALL=C $NAVARRO "$4" $6.Z
		LC_ALL=C $NAVARRO "$4" $6.Z
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $NAVARRO "$4" $6.Z
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> navarro.txt
		done
		echo "\"navarro\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	fi

	echo "\"MatchesZ\": $MATCHESZ," >> $JSON
	echo "\"MatchesGG\": $MATCHESGG," >> $JSON
	echo "\"MatchesH\": $MATCHESH," >> $JSON
	echo "\"MatchesN\": $MATCHESN" >> $JSON
}

iterate_sizes() {
	FILE=$1

	# Iterate through file sizes
	for var in ${@:4}
	do
		REPS=$3
		COUNTER=0
		# echo "Processing files original$var.txt{rp,gz}"
		JSON=$var$2".json"
		SIZE=$var
		echo "[" > $JSON
		echo "{" >> $JSON
		rm -f gsearch.txt zgrep_lz4.txt zrg_lz4.txt zgrep_zstd.txt zrg_zstd.txt zgrep_gzip.txt zrg_gzip.txt navarro.txt lzgrep.txt grep.txt ripgrep.txt zrg_lz4_p.txt zgrep_lz4_p.txt zrg_zstd_p.txt zgrep_zstd_p.txt zgrep_gzip_p.txt zrg_gzip_p.txt zhs_lz4_p.txt hyperscan.txt zpc_lz4_p.txt pcregrep.txt zhs_zstd_p.txt
		run_simple_case "${reh[0]}" "${regsearch[0]}" "${regrep[0]}" "${ren[0]}" "${relz[0]}" $FILE$SIZE".txt" 0

		for i in `seq 1 $((${#reh[@]}-1))`
		do
			echo "}," >> $JSON
			echo "{" >> $JSON
			run_simple_case "${reh[$i]}" "${regsearch[$i]}" "${regrep[$i]}" "${ren[$i]}" "${relz[$i]}" $FILE$SIZE".txt" $i
		done

		echo "}," >> $JSON
		echo "{" >> $JSON
		echo "\"Regex\": \"All\"," >> $JSON

		if [[ $DE_COMPRESSORS == 1 ]]; then
			# (De)compression
			REPS=3
			rm $TMP
			LC_ALL=C $ZSTD -dc $FILE$SIZE".txt".zst > /dev/null
			for i in `seq 1 $REPS`; do
				BEGIN=$(date +%s%3N)
				LC_ALL=C $ZSTD -dc $FILE$SIZE".txt".zst > /dev/null
				END=$(date +%s%3N)
				echo $((END-BEGIN)) >> $TMP
			done
			echo "\"zstd_d\": "`$STATS_SCRIPT $TMP`"," >> $JSON
			FILESIZE=$(stat -c%s $FILE$SIZE.txt.zst)
			echo "\"zstd_s\": $FILESIZE," >> $JSON

			rm $TMP
			LC_ALL=C $LZ4 -dc $FILE$SIZE".txt".lz4 > /dev/null
			for i in `seq 1 $REPS`; do
				BEGIN=$(date +%s%3N)
				LC_ALL=C $LZ4 -dc $FILE$SIZE".txt".lz4 > /dev/null
				END=$(date +%s%3N)
				echo $((END-BEGIN)) >> $TMP
			done
			echo "\"lz4_d\": "`$STATS_SCRIPT $TMP`"," >> $JSON
			FILESIZE=$(stat -c%s $FILE$SIZE.txt.lz4)
			echo "\"lz4_s\": $FILESIZE," >> $JSON

			rm $TMP
			cp $FILE$SIZE".txt" "a.txt"
			LC_ALL=C $LZW -f "a.txt"
			LC_ALL=C $LZW -dc "a.txt.Z" > /dev/null
			for i in `seq 1 $REPS`; do
				BEGIN=$(date +%s%3N)
				LC_ALL=C $LZW -dc "a.txt.Z" > /dev/null
				END=$(date +%s%3N)
				echo $((END-BEGIN)) >> $TMP
			done
			echo "\"LZW_d\": "`$STATS_SCRIPT $TMP`"," >> $JSON
			FILESIZE=$(stat -c%s $FILE$SIZE.txt.Z)
			echo "\"lzw_s\": $FILESIZE," >> $JSON

			rm $TMP
			LC_ALL=C $DESPAIR $FILE$SIZE".txt" > /dev/null
			for i in `seq 1 $REPS`; do
				BEGIN=$(date +%s%3N)
				LC_ALL=C $DESPAIR $FILE$SIZE".txt" > /dev/null
				END=$(date +%s%3N)
				echo $((END-BEGIN)) >> $TMP
			done
			echo "\"despair\": "`$STATS_SCRIPT $TMP`"," >> $JSON
			FILESIZE=$(stat -c%s $FILE$SIZE.txt.rp)
			echo "\"repair_s\": $FILESIZE," >> $JSON

			rm $TMP
			cp $FILE$SIZE".txt" "a.txt"
			LC_ALL=C $GZIP -f "a.txt"
			LC_ALL=C $GZIP -dc "a.txt.gz" > /dev/null
			for i in `seq 1 $REPS`; do
				BEGIN=$(date +%s%3N)
				LC_ALL=C $GZIP -dc "a.txt.gz" > /dev/null
				END=$(date +%s%3N)
				echo $((END-BEGIN)) >> $TMP
			done
			echo "\"gzip_d\": "`$STATS_SCRIPT $TMP`"," >> $JSON
			FILESIZE=$(stat -c%s $FILE$SIZE.txt.gz)
			echo "\"gzip_s\": $FILESIZE," >> $JSON

			rm $TMP
			LC_ALL=C $ZSTD -c --ultra -22 $FILE$SIZE".txt" > /dev/null
			for i in `seq 1 $REPS`; do
				BEGIN=$(date +%s%3N)
				LC_ALL=C $ZSTD -c --ultra -22 $FILE$SIZE".txt" > /dev/null
				END=$(date +%s%3N)
				echo $((END-BEGIN)) >> $TMP
			done
			echo "\"zstd\": "`$STATS_SCRIPT $TMP`"," >> $JSON

			rm $TMP
			LC_ALL=C $LZ4 -c -9 $FILE$SIZE".txt" > /dev/null
			for i in `seq 1 $REPS`; do
				BEGIN=$(date +%s%3N)
				LC_ALL=C $LZ4 -c -9 $FILE$SIZE".txt" > /dev/null
				END=$(date +%s%3N)
				echo $((END-BEGIN)) >> $TMP
			done
			echo "\"lz4\": "`$STATS_SCRIPT $TMP`"," >> $JSON

			rm $TMP
			cp $FILE$SIZE".txt" "a.txt"
			LC_ALL=C $LZW -c "a.txt" > /dev/null
			rm a.txt.Z
			for i in `seq 1 $REPS`; do
				BEGIN=$(date +%s%3N)
				LC_ALL=C $LZW -c "a.txt" > /dev/null
				END=$(date +%s%3N)
				echo $((END-BEGIN)) >> $TMP
				rm a.txt.Z
			done
			echo "\"LZW\": "`$STATS_SCRIPT $TMP`"," >> $JSON

			rm $TMP
			cp $FILE$SIZE".txt" "a.txt"
			LC_ALL=C $GZIP -c -9 "a.txt" > /dev/null
			rm a.txt.gz
			for i in `seq 1 $REPS`; do
				BEGIN=$(date +%s%3N)
				LC_ALL=C $GZIP -c -9 "a.txt" > /dev/null
				END=$(date +%s%3N)
				echo $((END-BEGIN)) >> $TMP
				rm a.txt.gz
			done
			echo "\"gzip\": "`$STATS_SCRIPT $TMP`"," >> $JSON

			rm $TMP
			LC_ALL=C $REPAIR $FILE$SIZE".txt" > /dev/null
			for i in `seq 1 $REPS`; do
				BEGIN=$(date +%s%3N)
				LC_ALL=C $REPAIR $FILE$SIZE".txt" > /dev/null
				END=$(date +%s%3N)
				echo $((END-BEGIN)) >> $TMP
			done
			echo "\"repair\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		fi

		echo "\"zearch\": "`$STATS_SCRIPT gsearch.txt`"," >> $JSON
		echo "\"grep\": "`$STATS_SCRIPT grep.txt`"," >> $JSON
		echo "\"hyperscan\": "`$STATS_SCRIPT hyperscan.txt`"," >> $JSON
		echo "\"zgrep_zstd_p\": "`$STATS_SCRIPT zgrep_zstd_p.txt`"," >> $JSON
		echo "\"zhs_zstd_p\": "`$STATS_SCRIPT zhs_zstd_p.txt`"," >> $JSON
		echo "\"zgrep_lz4_p\": "`$STATS_SCRIPT zgrep_lz4_p.txt`"," >> $JSON
		echo "\"zhs_lz4_p\": "`$STATS_SCRIPT zhs_lz4_p.txt`"," >> $JSON
		echo "\"GNgrep\": "`$STATS_SCRIPT navarro.txt` >> $JSON
		echo "}" >> $JSON
		echo "]" >> $JSON

	done

}

#############################
##
##	TESTS
##

reh=("what.*$" "HTTP.*$" "..*$" "I .* you.*$" " [a-z]{4} .*$" "[0-9]{2}/((Jun)|(Jul)|(Aug))/[0-9]{4}.*$" " [a-z]*[a-z]{3} .*$" "[0-9]{4}.*$")
regsearch=("what" "HTTP" "." "I .* you" " [a-z]{4} " "[0-9]{2}/((Jun)|(Jul)|(Aug))/[0-9]{4}" " [a-z]*[a-z]{3} " "[0-9]{4}")
regrep=("what" "HTTP" "." "I .* you" " [a-z]\{4\} " "[0-9]\{2\}/\(\(Jun\)\|\(Jul\)\|\(Aug\)\)/[0-9]\{4\}" " [a-z]*[a-z]\{3\} " "[0-9]\{4\}")
ren=("what[^\n]*\n" "HTTP[^\n]*\n" "[^\n][^\n]*\n" "I [^\n]* you[^\n]*\n" " [a-z][a-z][a-z][a-z] [^\n]*\n" "[0-9][0-9]/((Jun)|(Jul)|(Aug))/[0-9][0-9][0-9][0-9][^\n]*\n" " [a-z]*[a-z][a-z][a-z] [^\n]*\n" "[0-9][0-9][0-9][0-9][^\n]*\n")
relz=("what" "HTTP" "." "I .* you" " [a-z]{4} " "[0-9]{2}/((Jun)|(Jul)|(Aug))/[0-9]{4}" " [a-z]*[a-z]{3} " "[0-9]{4}")

iterate_sizes ../benchmark/yes/original What 30 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB
# iterate_sizes ../benchmark/gutenberg/original Gutenberg 30 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB
# iterate_sizes ../benchmark/subs/original Subtitles 30 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB
# iterate_sizes ../benchmark/logs/original Logs 30 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB

# iterate_sizes ../benchmark/gutenberg/original Gutenberg 30 1KB 10KB 25KB 50KB 75KB 100KB
# iterate_sizes ../benchmark/subs/original Subtitles 30 1KB 10KB 25KB 50KB 75KB 100KB
# iterate_sizes ../benchmark/logs/original Logs 30 1KB 10KB 25KB 50KB 75KB 100KB
