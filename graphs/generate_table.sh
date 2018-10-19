#!/bin/bash
#
# Author:	Pedro Valero
#
# Description: Script to compare with other tools.
#
# Date: 13/10/2017

RG="../../ripgrep-0.10.0-x86_64-unknown-linux-musl/rg"
REPAIR="../../repair110811/repair"
DESPAIR="../../repair110811/despair"
GREP="../../grep-3.1/src/grep"
PCREGREP="../../pcre2-10.32/pcre2grep"
ZEARCH="../zearch"
HYPERSCAN="./hyperscan"
LZ4="../../lz4/lz4"
ZSTD="../../zstd/zstd"
NAVARRO="../../code/search"
LZGREP="../../lzgrep/lzgrep"
LZW="../../code/compress"
GZIP="../../gzip-1.9/gzip"
COUNTER=0
TOCACTUS="./cactus-plot.py"
STATS="stats.txt"
# TIMEOUTRATIO=50
STATS_COUNTER=0

INDEX="index.html"

TMP="tmp.txt"
STATS_SCRIPT="./statistics.py"

## Required size of the originals (+ .rp, .zst, .gz):
##
## 100KB
## 500KB
## 1MB
## 2MB
## 5MB
## 25MB
## 100MB

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
	PCTO=0

	BEGIN=$(date +%s%3N)
	for i in `seq 1 $REPS`; do $ZEARCH -c "$1" $6.rp 2>&1 1>/dev/null; done
	END=$(date +%s%3N)

	MATCHESR=$(LC_ALL=C $TIMEOUT $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1" $6 2>/dev/null)
	if [[ $? == 124 ]]; then RGTO=1; MATCHESR=0; fi
	if [ -z "$MATCHESR" ]; then MATCHESR=0; fi

	MATCHESGG=$(LC_ALL=C $TIMEOUT $GREP -c "$3" $6 2>/dev/null)
	if [[ $? == 124 ]]; then GTO=1; MATCHESGG=0; fi

	MATCHESZ=$($ZEARCH -c "$1" $6.rp 2>/dev/null)

	MATCHESH=$(LC_ALL=C $TIMEOUT $HYPERSCAN "$1" $6 2>/dev/null)
	if [[ $? == 124 ]]; then HTO=1; MATCHESH=0; fi

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

		LC_ALL=C taskset -c 3 $LZ4 -dc $6.lz4 | LC_ALL=C taskset -c 3 $GREP -c "$3"
		rm $TMP
		LC_ALL=C taskset -c 3 $LZ4 -dc $6.lz4 | LC_ALL=C taskset -c 3 $GREP -c "$3"
		LC_ALL=C taskset -c 3 $LZ4 -dc $6.lz4 | LC_ALL=C taskset -c 3 $GREP -c "$3"
		LC_ALL=C taskset -c 3 $LZ4 -dc $6.lz4 | LC_ALL=C taskset -c 3 $GREP -c "$3"
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C taskset -c 3 $LZ4 -dc $6.lz4 | LC_ALL=C taskset -c 3 $GREP -c "$3"
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> zgrep_lz4.txt
		done
		echo "\"zgrep_lz4\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	fi

	# RIPGREP

	if [[ $RGTO == 1 ]]; then
		rm $TMP
		for i in `seq 1 $REPS`; do
			echo 20000 >> $TMP
			echo 20000 >> zrg_zstd.txt
			echo 20000 >> ripgrep.txt
			echo 20000 >> zrg_lz4.txt
			echo 20000 >> zrg_lz4_p.txt
			echo 20000 >> zrg_zstd_p.txt
		done
		echo "\"zrg_zstd\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zrg_lz4\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zrg_gzip\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zrg_zstd_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zrg_lz4_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zrg_gzip_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"ripgrep\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	else
		LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1" $6
		rm $TMP
		LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1" $6
		LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1" $6
		LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1" $6
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1" $6
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> ripgrep.txt
		done
		echo "\"ripgrep\": "`$STATS_SCRIPT $TMP`"," >> $JSON
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

	# # LZGREP
	# if [ $7 -le 1 ]; then
	# 	if [[ $LZTO == 1 ]]; then
	# 		rm $TMP
	# 		for i in `seq 1 $REPS`; do
	# 			echo 20000 >> $TMP
	# 			echo 20000 >> lzgrep.txt
	# 		done
	# 		echo "\"lzgrep\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	# 	else
	# 		LC_ALL=C $LZGREP $FLAG -c "$5" $6.Z
	# 		rm $TMP
	# 		LC_ALL=C $LZGREP $FLAG -c "$5" $6.Z
	# 		LC_ALL=C $LZGREP $FLAG -c "$5" $6.Z
	# 		LC_ALL=C $LZGREP $FLAG -c "$5" $6.Z
	# 		for i in `seq 1 $REPS`; do
	# 			BEGIN=$(date +%s%3N)
	# 			LC_ALL=C $LZGREP $FLAG -c "$5" $6.Z
	# 			END=$(date +%s%3N)
	# 			echo $((END-BEGIN)) >> $TMP
	# 			echo $((END-BEGIN)) >> lzgrep.txt
	# 		done
	# 		echo "\"lzgrep\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	# 	fi
	# fi

	echo "\"MatchesZ\": $MATCHESZ," >> $JSON
	echo "\"MatchesGG\": $MATCHESGG," >> $JSON
	# echo "\"MatchesP\": $MATCHESP," >> $JSON
	echo "\"MatchesR\": $MATCHESR," >> $JSON
	echo "\"MatchesH\": $MATCHESH," >> $JSON
	echo "\"MatchesN\": $MATCHESN," >> $JSON
	echo "\"MatchesL\": $MATCHESL" >> $JSON
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
		rm -f gsearch.txt zgrep_lz4.txt zrg_lz4.txt zgrep_zstd.txt zrg_zstd.txt zgrep_gzip.txt zrg_gzip.txt navarro.txt lzgrep.txt grep.txt ripgrep.txt zrg_lz4_p.txt zgrep_lz4_p.txt zrg_zstd_p.txt zgrep_zstd_p.txt zgrep_gzip_p.txt zrg_gzip_p.txt zhs_lz4_p.txt hyperscan.txt zpc_lz4_p.txt pcregrep.txt
		run_simple_case "${rerp[0]}" "${regsearch[0]}" "${regrep[0]}" "${ren[0]}" "${relz[0]}" $FILE$SIZE".txt" 0

		for i in `seq 1 $((${#rerp[@]}-1))`
		do
			echo "}," >> $JSON
			echo "{" >> $JSON
			run_simple_case "${rerp[$i]}" "${regsearch[$i]}" "${regrep[$i]}" "${ren[$i]}" "${relz[$i]}" $FILE$SIZE".txt" $i
		done

		echo "}," >> $JSON
		echo "{" >> $JSON
		echo "\"Regex\": \"All\"," >> $JSON

		# (De)compression
		REPS=3
		rm $TMP
		LC_ALL=C $ZSTD -dc $FILE$SIZE".txt".zst | tail -n1 > /dev/null
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $ZSTD -dc $FILE$SIZE".txt".zst | tail -n1 > /dev/null
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
		done
		echo "\"zstd_d\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		FILESIZE=$(stat -c%s $FILE$SIZE.txt.zst)
		echo "\"zstd_s\": $FILESIZE," >> $JSON

		rm $TMP
		LC_ALL=C $LZ4 -dc $FILE$SIZE".txt".lz4 | tail -n1 > /dev/null
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $LZ4 -dc $FILE$SIZE".txt".lz4 | tail -n1 > /dev/null
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
		done
		echo "\"lz4_d\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		FILESIZE=$(stat -c%s $FILE$SIZE.txt.lz4)
		echo "\"lz4_s\": $FILESIZE," >> $JSON

		rm $TMP
		cp $FILE$SIZE".txt" "a.txt"
		LC_ALL=C $LZW -f "a.txt"
		LC_ALL=C $LZW -dc "a.txt.Z" | tail -n1 > /dev/null
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $LZW -dc "a.txt.Z" | tail -n1 > /dev/null
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
		LC_ALL=C $GZIP -dc "a.txt.gz" | tail -n1 > /dev/null
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $GZIP -dc "a.txt.gz" | tail -n1 > /dev/null
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

		echo "\"ripgrep\": "`$STATS_SCRIPT ripgrep.txt`"," >> $JSON
		echo "\"grep\": "`$STATS_SCRIPT grep.txt`"," >> $JSON
		echo "\"hyperscan\": "`$STATS_SCRIPT hyperscan.txt`"," >> $JSON
		echo "\"zearch\": "`$STATS_SCRIPT gsearch.txt`"," >> $JSON
		echo "\"zgrep_lz4\": "`$STATS_SCRIPT zgrep_lz4.txt`"," >> $JSON
		# echo "\"zhs_lz4_p\": "`$STATS_SCRIPT zhs_lz4_p.txt`"," >> $JSON
		# echo "\"pcregrep\": "`$STATS_SCRIPT pcregrep.txt`"," >> $JSON
		# echo "\"zpc_lz4_p\": "`$STATS_SCRIPT zpc_lz4_p.txt`"," >> $JSON
		# echo "\"zrg_lz4\": "`$STATS_SCRIPT zrg_lz4.txt`"," >> $JSON
		# echo "\"zrg_zstd\": "`$STATS_SCRIPT zrg_zstd.txt`"," >> $JSON
		# echo "\"zgrep_zstd\": "`$STATS_SCRIPT zgrep_zstd.txt`"," >> $JSON
		# echo "\"zgrep_gzip\": "`$STATS_SCRIPT zgrep_gzip.txt`"," >> $JSON
		# echo "\"zrg_lz4_p\": "`$STATS_SCRIPT zrg_lz4_p.txt`"," >> $JSON
		echo "\"zgrep_lz4_p\": "`$STATS_SCRIPT zgrep_lz4_p.txt`"," >> $JSON
		# echo "\"zrg_zstd_p\": "`$STATS_SCRIPT zrg_zstd_p.txt`"," >> $JSON
		# echo "\"zgrep_zstd_p\": "`$STATS_SCRIPT zgrep_zstd_p.txt`"," >> $JSON
		# echo "\"zgrep_gzip_p\": "`$STATS_SCRIPT zgrep_gzip_p.txt`"," >> $JSON
		echo "\"GNgrep\": "`$STATS_SCRIPT navarro.txt` >> $JSON
		# echo "\"LZgrep\": "`$STATS_SCRIPT lzgrep.txt` >> $JSON
		echo "}" >> $JSON
		echo "]" >> $JSON

	done

}

#############################
##
##	SUBTITLES
##
# regname=("Hello" "," "my" "name" "is" "Pedro")
# rerp=("Hello" "," "my" "name" "is" "Pedro")
# regsearch=("Hello" "," "my" "name" "is" "Pedro")
# regrep=("Hello" "," "my" "name" "is" "Pedro")
# ren=("Hello" "," "my" "name" "is" "Pedro")

rerp=("what" "HTTP" "." "I .* you" " [a-z]{4} " "[0-9]{2}/((Jun)|(Jul)|(Aug))/[0-9]{4}" " [a-z]*[a-z]{3} " "[0-9]{4}")
regsearch=("what" "HTTP" "." "I .* you" " [a-z]{4} " "[0-9]{2}/((Jun)|(Jul)|(Aug))/[0-9]{4}" " [a-z]*[a-z]{3} " "[0-9]{4}")
regrep=("what" "HTTP" "." "I .* you" " [a-z]\{4\} " "[0-9]\{2\}/\(\(Jun\)\|\(Jul\)\|\(Aug\)\)/[0-9]\{4\}" " [a-z]*[a-z]\{3\} " "[0-9]\{4\}")
ren=("what" "HTTP" "." "I .* you" " [a-z][a-z][a-z][a-z] " "[0-9][0-9]/((Jun)|(Jul)|(Aug))/[0-9][0-9][0-9][0-9]" " [a-z]*[a-z][a-z][a-z] " "[0-9][0-9][0-9][0-9]")
relz=("what" "HTTP" "." "I .* you" " [a-z]{4} " "[0-9]{2}/((Jun)|(Jul)|(Aug))/[0-9]{4}" " [a-z]*[a-z]{3} " "[0-9]{4}")

iterate_sizes ../benchmark/gutenberg/original gutenberg 30 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB
iterate_sizes ../benchmark/subs/original Subtitles 30 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB
iterate_sizes ../benchmark/logs/original Logs 30 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB
