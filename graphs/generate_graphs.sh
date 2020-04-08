#!/bin/bash
#
# Author:	Pedro Valero
#
# Description: Script to compare with other tools.
#
# Date: 19/10/2018

RG="../../ripgrep-0.10.0-x86_64-unknown-linux-musl/rg"
REPAIR="../../Re-Pair/repair110811/repair"
DESPAIR="../../Re-Pair/repair110811/despair"
GREP="../../grep-3.3/src/grep"
ZEARCH="../zearch"
HYPERSCAN="./hyperscan"
LZ4="../../lz4/lz4"
ZSTD="../../zstd/zstd"
NAVARRO="../../code/search"
LZGREP="../../lzgrep/lzgrep"
LZW="../../code/compress"
GZIP="../../gzip-1.9/gzip"
COUNTER=0
TOCACTUS="./cactus_plot.py"
STATS_COUNTER=0

INDEX="index.html"

TMP="tmp.txt"
STATS_SCRIPT="./statistics.py"

# args: regex for rg, regex for zearch, regex por grep input (compress .rp)
run_simple_case() {
	COUNTER=$((COUNTER+1))
	echo "\"Regex\": \"r$COUNTER\"," >> $JSON

	TIMEOUT="timeout 20"
	RGTO=0
	GTO=0
	LZTO=0
	NTO=0
	NSF=0
	HTO=0

	BEGIN=$(date +%s%3N)
	for i in `seq 1 $REPS`; do $ZEARCH -c "$1" $6.rp 2>&1 1>/dev/null; done
	END=$(date +%s%3N)

	MATCHESR=$(LC_ALL=C $TIMEOUT $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1" $6 2>/dev/null)
	if [[ $? == 124 ]]; then RGTO=1; MATCHESR=0; fi
	if [ -z "$MATCHESR" ]; then MATCHESR=0; fi

	MATCHESGG=$(LC_ALL=C $TIMEOUT $GREP -c "$3" $6 2>/dev/null)
	if [[ $? == 124 ]]; then GTO=1; MATCHESGG=0; fi

	MATCHESZ=$(LC_ALL=C $ZEARCH -c "$1" $6.rp 2>/dev/null)

	MATCHESH=$(LC_ALL=C $TIMEOUT $HYPERSCAN "$1.*$" $6 2>/dev/null)
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
			echo 10000 >> $TMP
			echo 10000 >> zgrep_lz4.txt
			echo 10000 >> zgrep_zstd.txt
			echo 10000 >> grep.txt
			echo 10000 >> zgrep_lz4_p.txt
			echo 10000 >> zgrep_zstd_p.txt
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
		echo "\"zhs_zstd_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	else
		LC_ALL=C $HYPERSCAN "$1.*$" $6
		rm $TMP
		LC_ALL=C $HYPERSCAN "$1.*$" $6
		LC_ALL=C $HYPERSCAN "$1.*$" $6
		LC_ALL=C $HYPERSCAN "$1.*$" $6
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $HYPERSCAN "$1.*$" $6
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> hyperscan.txt
		done
		echo "\"hyperscan\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1.*$"
		rm $TMP
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1.*$"
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1.*$"
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1.*$"
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $HYPERSCAN "$1.*$"
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> zhs_lz4_p.txt
		done
		echo "\"zhs_lz4_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $HYPERSCAN "$1.*$"
		rm $TMP
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $HYPERSCAN "$1.*$"
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $HYPERSCAN "$1.*$"
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $HYPERSCAN "$1.*$"
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $HYPERSCAN "$1.*$"
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> zhs_zstd_p.txt
		done
		echo "\"zhs_zstd_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON

	fi

	# RIPGREP

	if [[ $RGTO == 1 ]]; then
		rm $TMP
		for i in `seq 1 $REPS`; do
			echo 10000 >> $TMP
			echo 10000 >> zrg_zstd.txt
			echo 10000 >> ripgrep.txt
			echo 10000 >> zrg_lz4.txt
			echo 10000 >> zrg_lz4_p.txt
			echo 10000 >> zrg_zstd_p.txt
		done
		echo "\"zrg_zstd\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zrg_lz4\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zrg_gzip\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zrg_zstd_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zrg_lz4_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"zrg_gzip_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON
		echo "\"ripgrep\": "`$STATS_SCRIPT $TMP`"," >> $JSON
	else
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1"
		rm $TMP
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1"
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1"
		LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1"
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $ZSTD -dc $6.zst | LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1"
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> zrg_zstd_p.txt
		done
		echo "\"zrg_zstd_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1"
		rm $TMP
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1"
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1"
		LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1"
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $LZ4 -dc $6.lz4 | LC_ALL=C $RG --dfa-size-limit 8G --regex-size-limit 8G -c "$1"
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
			echo $((END-BEGIN)) >> zrg_lz4_p.txt
		done
		echo "\"zrg_lz4_p\": "`$STATS_SCRIPT $TMP`"," >> $JSON

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

	echo "\"MatchesZ\": $MATCHESZ," >> $JSON
	echo "\"MatchesGG\": $MATCHESGG," >> $JSON
	echo "\"MatchesR\": $MATCHESR," >> $JSON
	echo "\"MatchesH\": $MATCHESH" >> $JSON
}

iterate_sizes() {
	FILE=$1

	# Iterate through file sizes
	for var in ${@:4}
	do
		REPS=$3
		COUNTER=0
		JSON=$var$2".json"
		SIZE=$var
		echo "[" > $JSON
		echo "{" >> $JSON
		rm -f gsearch.txt zgrep_lz4.txt zrg_lz4.txt zgrep_zstd.txt zrg_zstd.txt zgrep_gzip.txt zrg_gzip.txt navarro.txt lzgrep.txt grep.txt ripgrep.txt zrg_lz4_p.txt zgrep_lz4_p.txt zrg_zstd_p.txt zgrep_zstd_p.txt zgrep_gzip_p.txt zrg_gzip_p.txt zhs_lz4_p.txt zhs_zstd_p.txt hyperscan.txt
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
		LC_ALL=C $ZSTD -dc $FILE$SIZE".txt".zst > /dev/null
		LC_ALL=C $ZSTD -dc $FILE$SIZE".txt".zst > /dev/null
		LC_ALL=C $ZSTD -dc $FILE$SIZE".txt".zst > /dev/null
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $ZSTD -dc $FILE$SIZE".txt".zst > /dev/null
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
		done
		echo "\"zstd\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		rm $TMP
		LC_ALL=C $LZ4 -dc $FILE$SIZE".txt".lz4 > /dev/null
		LC_ALL=C $LZ4 -dc $FILE$SIZE".txt".lz4 > /dev/null
		LC_ALL=C $LZ4 -dc $FILE$SIZE".txt".lz4 > /dev/null
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $LZ4 -dc $FILE$SIZE".txt".lz4 > /dev/null
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
		done
		echo "\"lz4\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		rm $TMP
		LC_ALL=C $DESPAIR $FILE$SIZE".txt" > /dev/null
		LC_ALL=C $DESPAIR $FILE$SIZE".txt" > /dev/null
		LC_ALL=C $DESPAIR $FILE$SIZE".txt" > /dev/null
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $DESPAIR $FILE$SIZE".txt" > /dev/null
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
		done
		echo "\"repair\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		rm $TMP
		cp $FILE$SIZE".txt" "a.txt"
		LC_ALL=C $GZIP -f "a.txt"
		LC_ALL=C $GZIP -dc "a.txt.gz" > /dev/null
		LC_ALL=C $GZIP -dc "a.txt.gz" > /dev/null
		LC_ALL=C $GZIP -dc "a.txt.gz" > /dev/null
		for i in `seq 1 $REPS`; do
			BEGIN=$(date +%s%3N)
			LC_ALL=C $GZIP -dc "a.txt.gz" > /dev/null
			END=$(date +%s%3N)
			echo $((END-BEGIN)) >> $TMP
		done
		echo "\"gzip\": "`$STATS_SCRIPT $TMP`"," >> $JSON

		echo "\"zearch\": "`$STATS_SCRIPT gsearch.txt`"," >> $JSON
		echo "\"grep\": "`$STATS_SCRIPT grep.txt`"," >> $JSON
		echo "\"ripgrep\": "`$STATS_SCRIPT ripgrep.txt`"," >> $JSON
		echo "\"hyperscan\": "`$STATS_SCRIPT hyperscan.txt`"," >> $JSON
		echo "\"zhs_lz4_p\": "`$STATS_SCRIPT zhs_lz4_p.txt`"," >> $JSON
		echo "\"zhs_zstd_p\": "`$STATS_SCRIPT zhs_zstd_p.txt`"," >> $JSON
		echo "\"zgrep_lz4_p\": "`$STATS_SCRIPT zgrep_lz4_p.txt`"," >> $JSON
		echo "\"zgrep_zstd_p\": "`$STATS_SCRIPT zgrep_zstd_p.txt`"," >> $JSON
		echo "\"zrg_lz4_p\": "`$STATS_SCRIPT zrg_lz4_p.txt`"," >> $JSON
		echo "\"zrg_zstd_p\": "`$STATS_SCRIPT zrg_zstd_p.txt` >> $JSON
		echo "}" >> $JSON
		echo "]" >> $JSON

		$TOCACTUS $JSON $var$2"_cactus.json" >/dev/null
		m4 -D__NAME__=$var$2 -D__SIZE__=$var -D__TYPE__=$2 script_classic.txt >> $INDEX
		m4 -D__NAME__=$var$2"_cactus" -D__SIZE__=$var -D__TYPE__=$2 script_cactus.txt >> $INDEX
	done
	echo "</div>" >> $INDEX

	echo "</script>" >> $INDEX
}

iterate_files () {
	echo "<center><h1 class=\"type\" onclick=\"hideIt(this)\">$2</h1></center>" >> $INDEX
	echo "<div class=\"list $2\">" >> $INDEX
	echo "<h2><center> Regular Expressions </center></h2>" >> $INDEX
	echo "<ul>" >> $INDEX
	for i in `seq 0 $((${#rerp[@]}-1))`
	do
		echo "<li>r$((i+1)): \"${regname[$i]}\",</li>" >> $INDEX
	done
	echo "</ul>" >> $INDEX
	echo "</div>" >> $INDEX

	echo "<script>" >> $INDEX
	echo "	var colors20 = d3.scale.category20();" >> $INDEX
  	echo "	var color = d3.scale.ordinal()" >> $INDEX
    echo "		.domain([\"zearch\",\"grep\",\"ripgrep\",\"hyperscan\",\"zhs_lz4_p\",\"zhs_zstd_p\",\"zgrep_lz4_p\",\"zgrep_zstd_p\",\"zrg_lz4_p\",\"zrg_zstd_p\",\"repair\",\"lz4\", \"zstd\",\"gzip\"])" >> $INDEX
	echo "		.range([\"#4363d8\",\"#ffd000\",\"#800000\",\"#808000\",\"#e6194B\",\"#fabebe\",\"#f032e6\",\"#e6beff\",\"#3cb44b\",\"#aaffc3\",\"#4363d8\",\"#f032e6\",\"#42d4f4\",\"#800000\"]);" >> $INDEX

   	echo "document.getElementById(\"p1\").style.color = color(\"zearch\");" >> $INDEX
	echo "document.getElementById(\"p2\").style.color = color(\"grep\");" >> $INDEX
	echo "document.getElementById(\"p3\").style.color = color(\"ripgrep\");" >> $INDEX
	echo "document.getElementById(\"p4\").style.color = color(\"hyperscan\");" >> $INDEX
	echo "document.getElementById(\"p5\").style.color = color(\"zhs_lz4_p\");" >> $INDEX
	echo "document.getElementById(\"p6\").style.color = color(\"zhs_zstd_p\");" >> $INDEX
	echo "document.getElementById(\"p7\").style.color = color(\"zgrep_lz4_p\");" >> $INDEX
	echo "document.getElementById(\"p8\").style.color = color(\"zgrep_zstd_p\");" >> $INDEX
	echo "document.getElementById(\"p9\").style.color = color(\"zrg_lz4_p\");" >> $INDEX
	echo "document.getElementById(\"p10\").style.color = color(\"zrg_zstd_p\");" >> $INDEX
	echo "document.getElementById(\"p11\").style.color = color(\"repair\");" >> $INDEX
	echo "document.getElementById(\"p12\").style.color = color(\"lz4\");" >> $INDEX
	echo "document.getElementById(\"p13\").style.color = color(\"zstd\");" >> $INDEX
	echo "document.getElementById(\"p14\").style.color = color(\"gzip\");" >> $INDEX

	echo "</script>" >> $INDEX

	echo "<div class=\"graphs $2\">" >> $INDEX
	echo "<h2><center> Graphs </center></h2>" >> $INDEX
	echo "<script>" >> $INDEX
	echo "// Set the color scale" >> $INDEX
	echo "" >> $INDEX
	echo "</script>" >> $INDEX

	STATS_COUNTER=0
	iterate_sizes "$@"
}

echo "<!DOCTYPE html>" > $INDEX
echo "<meta charset=\"utf-8\">" >> $INDEX

echo "<script src=\"https://d3js.org/d3.v3.min.js\"></script>" >> $INDEX
echo "<script src=\"https://cdn.plot.ly/plotly-latest.min.js\"></script>" >> $INDEX
echo "<script src=\"https://labratrevenge.com/d3-tip/javascripts/d3.tip.v0.6.3.js\"></script>" >> $INDEX

echo "<style>" >> $INDEX
echo "path { " >> $INDEX
echo "    stroke-width: 2;" >> $INDEX
echo "    fill: none;" >> $INDEX
echo "    stroke-linejoin: round;" >> $INDEX
echo "    stroke-linecap: round;" >> $INDEX
echo "}" >> $INDEX
echo "circle { " >> $INDEX
echo "  stroke-width: 3;" >> $INDEX
echo "}" >> $INDEX
echo ".axis path," >> $INDEX
echo ".axis line {" >> $INDEX
echo "  fill: none;" >> $INDEX
echo "  stroke: grey;" >> $INDEX
echo "  stroke-width: 4;" >> $INDEX
echo "  shape-rendering: crispEdges;" >> $INDEX
echo "}" >> $INDEX
echo ".legend, .label, .hover-text{" >> $INDEX
echo "    font-size: 20px;" >> $INDEX
echo "    background-color: white;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "svg {" >> $INDEX
echo "  top: 300px;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "h1, h2, h3, h4, h5, h6 {" >> $INDEX
echo "  float: left;" >> $INDEX
echo "  width: 100%;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "ul {" >> $INDEX
echo "  width: 100%;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "li {" >> $INDEX
echo "    display: block;" >> $INDEX
echo "    float: left;" >> $INDEX
echo "    font-size: 23px;" >> $INDEX
echo "    margin-right: 20px;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "div {" >> $INDEX
echo "  font-size: 20px;" >> $INDEX
echo "	float: none;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo ".list {" >> $INDEX
echo "	width: 100%;" >> $INDEX
echo "  float: left;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo ".graphs {" >> $INDEX
echo "  float: center;" >> $INDEX
echo "	margin-top: 10px;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "body {" >> $INDEX
echo "  float: left;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "p {" >> $INDEX
echo "  font-weight: bold;" >> $INDEX
echo "	font-size: 23px;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "a {" >> $INDEX
echo "  color: inherit;" >> $INDEX
echo "}" >> $INDEX
echo ".type {" >> $INDEX
echo "	color: blue;" >> $INDEX
echo "	font-weight: bold;" >> $INDEX
echo "	font-size: 60px;" >> $INDEX
echo "}" >> $INDEX
echo ".d3-tip {" >> $INDEX
echo "  line-height: 1;" >> $INDEX
echo "  font-weight: bold;" >> $INDEX
echo "  padding: 12px;" >> $INDEX
echo "  background: rgba(0, 0, 0, 0.8);" >> $INDEX
echo "  color: #fff;" >> $INDEX
echo "  border-radius: 2px;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "/* Creates a small triangle extender for the tooltip */" >> $INDEX
echo ".d3-tip:after {" >> $INDEX
echo "  box-sizing: border-box;" >> $INDEX
echo "  display: inline;" >> $INDEX
echo "  font-size: 10px;" >> $INDEX
echo "  width: 100%;" >> $INDEX
echo "  line-height: 1;" >> $INDEX
echo "  color: rgba(0, 0, 0, 0.8);" >> $INDEX
echo "  content: \"\25BC\";" >> $INDEX
echo "  position: absolute;" >> $INDEX
echo "  text-align: center;" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "/* Style northward tooltips differently */" >> $INDEX
echo ".d3-tip.n:after {" >> $INDEX
echo "  margin: -1px 0 0 0;" >> $INDEX
echo "  top: 100%;" >> $INDEX
echo "  left: 0;" >> $INDEX
echo "}" >> $INDEX
echo "</style>" >> $INDEX

echo "<script>" >> $INDEX
echo "function hideIt(d) {" >> $INDEX
echo "    var l = document.getElementsByClassName(d.textContent);" >> $INDEX
echo "    for (var i = 0; i < l.length; i++) {" >> $INDEX
echo "      if(l[i].style.display=='none'){" >> $INDEX
echo "        l[i].style.display='block';" >> $INDEX
echo "        d.style.color='blue';" >> $INDEX
echo "      } else {" >> $INDEX
echo "        l[i].style.display='none';" >> $INDEX
echo "        d.style.color='grey';" >> $INDEX
echo "      }" >> $INDEX
echo "    }" >> $INDEX
echo "" >> $INDEX
echo "}" >> $INDEX
echo "" >> $INDEX
echo "function checkbox_clicked(checkboxElem) {" >> $INDEX
echo "  if (checkboxElem.checked) {" >> $INDEX
echo "    document.getElementById(checkboxElem.parentNode.attributes[\"name\"].nodeValue).style.display='none';" >> $INDEX
echo "    checkboxElem.parentNode.style.color='grey';    " >> $INDEX
echo "  } else {" >> $INDEX
echo "    document.getElementById(checkboxElem.parentNode.attributes[\"name\"].nodeValue).style.display='block';" >> $INDEX
echo "    checkboxElem.parentNode.style.color='black';    " >> $INDEX
echo "  }" >> $INDEX
echo "}" >> $INDEX
echo "</script>" >> $INDEX

echo "<div>" >> $INDEX
echo "<h1><center> Tools </center></h1>" >> $INDEX
echo "<p id=\"p1\"> zearch:</p>" >> $INDEX
echo "<p id=\"p2\"> grep:</p>" >> $INDEX
echo "<p id=\"p3\"> ripgrep:</p>" >> $INDEX
echo "<p id=\"p4\"> hyperscan:</p>" >> $INDEX
echo "<p id=\"p5\"> lz4|hyperscan:</p>" >> $INDEX
echo "<p id=\"p6\"> zstd|hyperscan:</p>" >> $INDEX
echo "<p id=\"p7\"> lz4|grep:</p>" >> $INDEX
echo "<p id=\"p8\"> zstd|grep:</p>" >> $INDEX
echo "<p id=\"p9\"> lz4|ripgrep:</p>" >> $INDEX
echo "<p id=\"p10\"> zstd|ripgrep:</p>" >> $INDEX
echo "<p id=\"p11\"> repair:</p>" >> $INDEX
echo "<p id=\"p12\"> lz4:</p>" >> $INDEX
echo "<p id=\"p13\"> zstd:</p>" >> $INDEX
echo "<p id=\"p14\"> gzip:</p>" >> $INDEX

echo "<br>" >> $INDEX
echo "<h1><center> Overview </center></h1>" >> $INDEX
echo "<div class=\"description\">" >> $INDEX
echo "The running time shown for each regular expression is the <a href=\"https://en.wikipedia.org/wiki/Confidence_interval\">confidence interval</a> computed over 30 runs, measured after a \"warming up\" run. When the confidence intervals of two experiments do not overlap then we have enough statistical evidence to claim that one tool outperforms the other on the given experiment." >> $INDEX
echo "If an execution takes more than 10 times the time required by zearch it is considered a timeout." >> $INDEX
echo "</div>" >> $INDEX
echo "<br>" >> $INDEX
echo "<hr>" >> $INDEX


#############################
##
##	SUBTITLES
##

regname=("." "wosel" "but where are you" "have" "I love you" "a" "\." "I .* you" "[a-z]{4}" "[0-9]{9}" " (19|20)[0-9]{2} " " [a-z]{2} " " [0-9]5[0-9]0[0-9]4[0-9]5[0-9] ")
rerp=("." "wosel" "but where are you" "have" "I love you" "a" "\." "I .* you" "[a-z]{4}" "[0-9]{9}" " (19|20)[0-9]{2} " " [a-z]{2} " " [0-9]5[0-9]0[0-9]4[0-9]5[0-9] ")
regsearch=("." "wosel" "but where are you" "have" "I love you" "a" "\." "I .* you" "[a-z]{4}" "[0-9]{9}" " (19|20)[0-9]{2} " " [a-z]{2} " " [0-9]5[0-9]0[0-9]4[0-9]5[0-9] ")
regrep=("." "wosel" "but where are you" "have" "I love you" "a" "\." "I .* you" "[a-z]\{4\}" "[0-9]\{9\}" " \(19\|20\)[0-9]\{2\} " " [a-z]\{2\} " " [0-9]5[0-9]0[0-9]4[0-9]5[0-9] ")
ren=("." "wosel" "but where are you" "have" "I love you" "a" "\." "I .* you" "[a-z][a-z][a-z][a-z]" "[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]" " (19|20)[0-9][0-9] " " [a-z][a-z] " " [0-9]5[0-9]0[0-9]4[0-9]5[0-9] ")
iterate_files ../benchmark/subs/original Subtitles 30 1KB 10KB 25KB 50KB 75KB 100KB 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB


#############################
##
##	Gutenberg
##

regname=("." "wosel" "but where are you" "have" "I love you" "a" "\." "I .* you" "[a-z]{4}" "[0-9]{9}" " (19|20)[0-9]{2} " " [a-z]{2} " " [0-9]5[0-9]0[0-9]4[0-9]5[0-9] ")
rerp=("." "wosel" "but where are you" "have" "I love you" "a" "\." "I .* you" "[a-z]{4}" "[0-9]{9}" " (19|20)[0-9]{2} " " [a-z]{2} " " [0-9]5[0-9]0[0-9]4[0-9]5[0-9] ")
regsearch=("." "wosel" "but where are you" "have" "I love you" "a" "\." "I .* you" "[a-z]{4}" "[0-9]{9}" " (19|20)[0-9]{2} " " [a-z]{2} " " [0-9]5[0-9]0[0-9]4[0-9]5[0-9] ")
regrep=("." "wosel" "but where are you" "have" "I love you" "a" "\." "I .* you" "[a-z]\{4\}" "[0-9]\{9\}" " \(19\|20\)[0-9]\{2\} " " [0-9]5[0-9]0[0-9]4[0-9]5[0-9] ")
ren=("." "wosel" "but where are you" "have" "I love you" "a" "\." "I .* you" "[a-z][a-z][a-z][a-z]" "[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]" " (19|20)[0-9][0-9] " " [a-z][a-z] " " [0-9]5[0-9]0[0-9]4[0-9]5[0-9] ")

iterate_files ../benchmark/gutenberg/original Gutenberg 30 1KB 10KB 25KB 50KB 75KB 100KB 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB

#############################
##
##	CSV
##

regname=("." "wosel" "1993" "20[0-9]{2}" ".*5" "[a-z]{5}" " [0-9]{9} ")
rerp=("." "wosel" "1993" "20[0-9]{2}" ".*5" "[a-z]{5}" " [0-9]{9} ")
regsearch=("." "wosel" "1993" "20[0-9]{2}" ".*5" "[a-z]{5}" " [0-9]{9} ")
regrep=("." "wosel" "1993" "20[0-9]\{2\}" ".*5" "[a-z]\{5\}" " [0-9]\{9\} ")
ren=("." "wosel" "1993" "20[0-9][0-9]" ".*5" "[a-z][a-z][a-z][a-z][a-z]" " [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] ")

iterate_files ../benchmark/csv/original CSV 30 1KB 10KB 25KB 50KB 75KB 100KB 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB

#############################
##
##	Logs
##

regname=("." "wosel" "port" "20[0-9]{2}" "([0-9]{3}\.){3}[0-9]" "[0-9]{4}" "([a-z]+\.)+[a-z]+ - -" "\"GET .*\" ([13-9]|2[1-9]|2-[1-9])" "(([0-9])|([0-2][0-9])|([3][0-1]))/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/[0-9]{4}" "(([0-9])|([0-2][0-9])|([3][0-1]))-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-[0-9]{4}")
rerp=("." "wosel" "port" "20[0-9]{2}" "([0-9]{3}\.){3}[0-9]" "[0-9]{4}" "([a-z]+\.)+[a-z]+ - -" "\"GET .*\" ([13-9]|2[1-9]|2-[1-9])" "(([0-9])|([0-2][0-9])|([3][0-1]))/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/[0-9]{4}" "(([0-9])|([0-2][0-9])|([3][0-1]))-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-[0-9]{4}")
regsearch=("." "wosel" "port" "20[0-9]{2}" "([0-9]{3}\.){3}[0-9]" "[0-9]{4}" "([a-z]+\.)+[a-z]+ - -" "\"GET .*\" ([13-9]|2[1-9]|2-[1-9])" "(([0-9])|([0-2][0-9])|([3][0-1]))/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/[0-9]{4}" "(([0-9])|([0-2][0-9])|([3][0-1]))-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-[0-9]{4}")
regrep=("." "wosel" "port" "20[0-9]\{2\}" "\([0-9]\{3\}\.\)\{3\}[0-9]" "[0-9]\{4\}" "\([a-z]\+\.\)\+[a-z]\+ - -" "\"GET .*\" \([13-9]\|2[1-9]\|2-[1-9]\)" "(([0-9])\|([0-2][0-9])\|([3][0-1]))/(Jan\|Feb\|Mar\|Apr\|May\|Jun\|Jul\|Aug\|Sep\|Oct\|Nov\|Dec)/[0-9]\{4\}" "(([0-9])\|([0-2][0-9])\|([3][0-1]))-(Jan\|Feb\|Mar\|Apr\|May\|Jun\|Jul\|Aug\|Sep\|Oct\|Nov\|Dec)-[0-9]\{4\}")
ren=("." "wosel" "port" "20[0-9][0-9]" "([0-9]{3}\.){3}[0-9]" "[0-9]{4}" "([a-z]+\.)+[a-z]+ - -" "\"GET .*\" ([13-9]|2[1-9]|2-[1-9])" "(([0-9])|([0-2][0-9])|([3][0-1]))/(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/[0-9]{4}" "(([0-9])|([0-2][0-9])|([3][0-1]))-(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-[0-9]{4}")

iterate_files ../benchmark/logs/original Logs 30 1KB 10KB 25KB 50KB 75KB 100KB 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB

#############################
##
##	Random
##

regname=("." "wosel" "0100101" "[0-1]{9}" "[0-1]{6,10}" "(0110101){2}" "[0-1]*1[0-1]{5}2" "[0-1]*1[0-1]{10}2" "[0-1]*1[0-1]{15}2" "[0-1]*1[0-1]{16}2" "[0-1]*1[0-1]{17}2" "[0-1]*1[0-1]{18}2" "[0-1]*1[0-1]{19}2" "[0-1]*1[0-1]{20}2")
rerp=("." "wosel" "0100101" "[0-1]{9}" "[0-1]{6,10}" "(0110101){2}" "[0-1]*1[0-1]{5}2" "[0-1]*1[0-1]{10}2" "[0-1]*1[0-1]{15}2" "[0-1]*1[0-1]{16}2" "[0-1]*1[0-1]{17}2" "[0-1]*1[0-1]{18}2" "[0-1]*1[0-1]{19}2" "[0-1]*1[0-1]{20}2")
regsearch=("." "wosel" "0100101" "[0-1]{9}" "[0-1]{6,10}" "(0110101){2}" "[0-1]*1[0-1]{5}2" "[0-1]*1[0-1]{10}2" "[0-1]*1[0-1]{15}2" "[0-1]*1[0-1]{16}2" "[0-1]*1[0-1]{17}2" "[0-1]*1[0-1]{18}2" "[0-1]*1[0-1]{19}2" "[0-1]*1[0-1]{20}2")
regrep=("." "wosel" "0100101" "[0-1]\{9\}" "[0-1]\{6,10\}" "(0110101)\{2\}" "[0-1]*1[0-1]\{5\}2" "[0-1]*1[0-1]\{10\}2" "[0-1]*1[0-1]\{15\}2" "[0-1]*1[0-1]\{16\}2" "[0-1]*1[0-1]\{17\}2" "[0-1]*1[0-1]\{18\}2" "[0-1]*1[0-1]\{19\}2" "[0-1]*1[0-1]\{20\}2")

# iterate_files ../benchmark/random01/original Random 30 1KB 10KB 25KB 50KB 75KB 100KB 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB

#############################
##
##	RandomL
##

regname=("." "wosel" "0100101" "[0-1]{9}" "[0-1]{6,10}" "(0110101){2}" "[0-1]*1[0-1]{5}2" "[0-1]*1[0-1]{10}2" "[0-1]*1[0-1]{15}2" "[0-1]*1[0-1]{20}2" "[0-1]*1[0-1]{25}2")
rerp=("." "wosel" "0100101" "[0-1]{9}" "[0-1]{6,10}" "(0110101){2}" "[0-1]*1[0-1]{5}2" "[0-1]*1[0-1]{10}2" "[0-1]*1[0-1]{15}2" "[0-1]*1[0-1]{20}2" "[0-1]*1[0-1]{25}2")
regsearch=("." "wosel" "0100101" "[0-1]{9}" "[0-1]{6,10}" "(0110101){2}" "[0-1]*1[0-1]{5}2" "[0-1]*1[0-1]{10}2" "[0-1]*1[0-1]{15}2" "[0-1]*1[0-1]{20}2" "[0-1]*1[0-1]{25}2")
regrep=("." "wosel" "0100101" "[0-1]\{9\}" "[0-1]\{6,10\}" "(0110101)\{2\}" "[0-1]*1[0-1]\{5\}2" "[0-1]*1[0-1]\{10\}2" "[0-1]*1[0-1]\{15\}2" "[0-1]*1[0-1]\{20\}2" "[0-1]*1[0-1]\{25\}2")

# iterate_files ../benchmark/random01lines/original RandomL 30 1KB 10KB 25KB 50KB 75KB 100KB 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB

#############################
##
##	Pedro
##

regname=("." "qwerty" "qwerti" "wosel" "[a-z]{5}")
rerp=("." "qwerty" "qwerti" "wosel" "[a-z]{5}")
regsearch=("." "qwerty" "qwerti" "wosel" "[a-z]{5}")
regrep=("." "qwerty" "qwerti" "wosel" "[a-z]\{5\}")

iterate_files ../benchmark/yes/original Qwerty 30 1KB 10KB 25KB 50KB 75KB 100KB 1MB 5MB 10MB 25MB 50MB 100MB 250MB 500MB