#!/bin/bash
#
# Author:	Pedro Valero
#
# Description: Script to generate benchmark files for zearch
#
# Date: 18/10/2018

# Variables to be set by the user
ZSTD="zstd"
LZ4="../../../lz4/lz4"
COMPRESS="../../../code/compress"
REPAIR="../../../Re-Pair/repair110811/repair"
GZIP="../../../gzip-1.9/gzip"

# Variables for the script. Modify them on your own responsibility
BLUE="\033[0;34m"
NC="\033[0m" # No Color

RANDOM=0 # Set to 1 to generate random files. Not used for the final experiments.

split_and_compress() {
	dd if=original.txt of=original500MB.txt bs=500 count=1048576
	dd if=original.txt of=original250MB.txt bs=250 count=1048576
	dd if=original.txt of=original100MB.txt bs=100 count=1048576
	dd if=original.txt of=original50MB.txt bs=50 count=1048576
	dd if=original.txt of=original25MB.txt bs=25 count=1048576
	dd if=original.txt of=original10MB.txt bs=10 count=1048576
	dd if=original.txt of=original5MB.txt bs=5 count=1048576
	dd if=original.txt of=original1MB.txt bs=1 count=1048576
	dd if=original.txt of=original100KB.txt bs=1 count=102400
	dd if=original.txt of=original75KB.txt bs=1 count=76800
	dd if=original.txt of=original50KB.txt bs=5 count=10240
	dd if=original.txt of=original25KB.txt bs=1 count=25600
	dd if=original.txt of=original10KB.txt bs=1 count=10240
	dd if=original.txt of=original1KB.txt bs=1 count=1024

	rm original.txt

	$ZSTD -k -f --ultra -22 original500MB.txt
	$ZSTD -k -f --ultra -22 original250MB.txt
	$ZSTD -k -f --ultra -22 original100MB.txt
	$ZSTD -k -f --ultra -22 original50MB.txt
	$ZSTD -k -f --ultra -22 original25MB.txt
	$ZSTD -k -f --ultra -22 original10MB.txt
	$ZSTD -k -f --ultra -22 original5MB.txt
	$ZSTD -k -f --ultra -22 original1MB.txt
	$ZSTD -k -f --ultra -22 original100KB.txt
	$ZSTD -k -f --ultra -22 original75KB.txt
	$ZSTD -k -f --ultra -22 original50KB.txt
	$ZSTD -k -f --ultra -22 original25KB.txt
	$ZSTD -k -f --ultra -22 original10KB.txt
	$ZSTD -k -f --ultra -22 original1KB.txt

	$LZ4 -f -9 -k -m original500MB.txt
	$LZ4 -f -9 -k -m original250MB.txt
	$LZ4 -f -9 -k -m original100MB.txt
	$LZ4 -f -9 -k -m original50MB.txt
	$LZ4 -f -9 -k -m original25MB.txt
	$LZ4 -f -9 -k -m original10MB.txt
	$LZ4 -f -9 -k -m original5MB.txt
	$LZ4 -f -9 -k -m original1MB.txt
	$LZ4 -f -9 -k -m original100KB.txt
	$LZ4 -f -9 -k -m original75KB.txt
	$LZ4 -f -9 -k -m original50KB.txt
	$LZ4 -f -9 -k -m original25KB.txt
	$LZ4 -f -9 -k -m original10KB.txt
	$LZ4 -f -9 -k -m original1KB.txt

	$GZIP -f -9 -k -m original500MB.txt
	$GZIP -f -9 -k -m original250MB.txt
	$GZIP -f -9 -k -m original100MB.txt
	$GZIP -f -9 -k -m original50MB.txt
	$GZIP -f -9 -k -m original25MB.txt
	$GZIP -f -9 -k -m original10MB.txt
	$GZIP -f -9 -k -m original5MB.txt
	$GZIP -f -9 -k -m original1MB.txt
	$GZIP -f -9 -k -m original100KB.txt
	$GZIP -f -9 -k -m original75KB.txt
	$GZIP -f -9 -k -m original50KB.txt
	$GZIP -f -9 -k -m original25KB.txt
	$GZIP -f -9 -k -m original10KB.txt
	$GZIP -f -9 -k -m original1KB.txt

	cp original500MB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original500MB.txt.Z
	cp original250MB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original250MB.txt.Z
	cp original100MB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original100MB.txt.Z
	cp original50MB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original50MB.txt.Z
	cp original25MB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original25MB.txt.Z
	cp original10MB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original10MB.txt.Z
	cp original5MB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original5MB.txt.Z
	cp original1MB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original1MB.txt.Z
	cp original100KB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original100KB.txt.Z
	cp original75KB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original75KB.txt.Z
	cp original50KB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original50KB.txt.Z
	cp original25KB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original25KB.txt.Z
	cp original10KB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original10KB.txt.Z
	cp original1KB.txt a.txt
	$COMPRESS a.txt
	mv a.txt.Z original1KB.txt.Z

	$REPAIR original500MB.txt
	$REPAIR original250MB.txt
	$REPAIR original100MB.txt
	$REPAIR original50MB.txt
	$REPAIR original25MB.txt
	$REPAIR original10MB.txt
	$REPAIR original5MB.txt
	$REPAIR original1MB.txt
	$REPAIR original100KB.txt
	$REPAIR original75KB.txt
	$REPAIR original50KB.txt
	$REPAIR original25KB.txt
	$REPAIR original10KB.txt
	$REPAIR original1KB.txt
}

echo "This script requires the following programs:"
echo "  zstd"
echo "  lz4"
echo "  repair"
echo "  compress"
echo "Please, confirm all of them are available and variables at the beginning of this file and set properly for your setup."
echo "Press any key to continue or ctrl+C to exit"
read

echo "Are you sure you want to download all files used for the experiments in \"Regular Expression Searching in Compressed Text\" by P. Ganty and P. Valero?"
echo "This requires 12 GB of disk space [y/n]"
read ANSWER

if [[ $ANSWER != "y" ]];
then
	exit
fi

echo -e "$BLUE============== Preparing Log files ==============$NC"

mkdir -p logs
cd logs

wget -q ftp://ita.ee.lbl.gov/traces/NASA_access_log_Jul95.gz
zcat NASA_access_log_Jul95.gz > logs.txt
rm NASA_access_log_Jul95.gz

wget -q ftp://ita.ee.lbl.gov/traces/NASA_access_log_Aug95.gz
zcat NASA_access_log_Aug95.gz >> logs.txt
rm NASA_access_log_Aug95.gz

wget -q ftp://ita.ee.lbl.gov/traces/usask_access_log.gz
zcat usask_access_log.gz >> logs.txt
rm usask_access_log.gz

echo "Data downloaded!!"

iconv --to-code US-ASCII -c logs.txt > original.txt 
rm logs.txt

echo "Generating files of different sizes and compressing them"
split_and_compress
cd ..

echo "DONE"
echo ""
echo "==================================================="
echo ""

echo -e "$BLUE============== Preparing Subtitles files ==============$NC"

mkdir -p subs
cd subs

wget -q http://opus.nlpl.eu/download.php?f=OpenSubtitles2016/mono/OpenSubtitles2016.en.gz
zcat download.php\?f\=OpenSubtitles2016%2Fmono%2FOpenSubtitles2016.en.gz > subs.txt
rm download.php\?f\=OpenSubtitles2016%2Fmono%2FOpenSubtitles2016.en.gz

echo "Data downloaded!!"

iconv --to-code US-ASCII -c subs.txt > original.txt 
rm subs.txt

echo "Generating files of different sizes and compressing them"
split_and_compress
cd ..

echo "DONE"
echo ""
echo "==================================================="
echo ""

echo -e "$BLUE============== Preparing Books files ==============$NC"

mkdir -p gutenberg
cd gutenberg

echo "Checkinf for some python libraries to download from google drive"
REQ=$(pip list 2> /dev/null | grep -c "requests")
if [[ $REQ -eq 0 ]]
then
	echo "Python library requests required"
	pip install --user requests
fi
echo "done"
echo "Downloading books from Gutenberg Dataset..."
echo "This may take a while..."
../download_gdrive.py 0B2Mzhc7popBga2RkcWZNcjlRTGM gutenberg.zip
unzip -u gutenberg.zip
cd Gutenberg/txt
../../../extract_books.sh
mv gutenberg.txt ../../
cd ../../

echo "Data downloaded!!"

iconv --to-code US-ASCII -c gutenberg.txt > tmp.txt 
rm gutenberg.txt
tr -d '\r' < tmp.txt > original.txt
rm tmp.txt

echo "Generating files of different sizes and compressing them"
split_and_compress
cd ..

echo "DONE"
echo ""
echo "==================================================="
echo ""

echo "Do you want to download all files used for the experiments? (even those not included in the paper) [y/n]"
read ALL_FILES

if [[ $ALL_FILES != "y" ]];
then
	exit
fi

echo -e "$BLUE============== Preparing JSON files ==============$NC"

mkdir -p json
cd json

wget -q http://data.gharchive.org/2015-01-01-{0..25}.json.gz
wget -q http://data.gharchive.org/2015-01-02-{0..15}.json.gz
zcat 2015-01-0*.json.gz > json.txt
rm 2015-01-0*.json.gz

echo "Data downloaded!!"

iconv --to-code US-ASCII -c json.txt > original.txt 
rm json.txt

echo "Generating files of different sizes and compressing them"
split_and_compress
cd ..

echo ""
echo "==================================================="
echo ""

echo -e "$BLUE============== Preparing CSV files ==============$NC"

mkdir -p csv
cd csv

wget -q http://storage.googleapis.com/books/ngrams/books/googlebooks-eng-all-2gram-20120701-go.gz
wget -q http://storage.googleapis.com/books/ngrams/books/googlebooks-eng-all-2gram-20120701-ww.gz
wget -q http://storage.googleapis.com/books/ngrams/books/googlebooks-eng-all-2gram-20120701-ab.gz
wget -q http://storage.googleapis.com/books/ngrams/books/googlebooks-eng-all-2gram-20120701-zz.gz
wget -q http://storage.googleapis.com/books/ngrams/books/googlebooks-eng-all-2gram-20120701-ye.gz

zcat googlebooks-eng-all-2gram-20120701-{go,ww,ab,zz,ye}.gz > tmp.txt
rm googlebooks-eng-all-2gram-20120701-{go,ww,ab,zz,ye}.gz
shuf tmp.txt > csv.txt
rm tmp.txt
echo "Data downloaded!!"

iconv --to-code US-ASCII -c csv.txt > original.txt 
rm csv.txt

echo "Generating files of different sizes and compressing them"
split_and_compress
cd ..

echo ""
echo "==================================================="
echo ""

echo -e "$BLUE============== Preparing querty files ==============$NC"
mkdir -p yes
cd yes

timeout 2 yes "qwerty" > yes.txt

echo "Data created!!"

iconv --to-code US-ASCII -c yes.txt > original.txt 
rm yes.txt

echo "Generating files of different sizes and compressing them"
split_and_compress
cd ..

echo ""
echo "==================================================="
echo ""

if [[ $RANDOM == 0 ]]; then
	echo "ALL FILES GENERATED"
	exit
fi

echo -e "$BLUE============== Preparing Random files ==============$NC"
mkdir -p random01
cd random01

cat /dev/urandom | tr -dc "01" | dd bs=10M count=50 iflags=fullblock 2>/dev/null > random.txt

echo "Data created!!"

iconv --to-code US-ASCII -c random.txt > original.txt 
rm random.txt

echo "Generating files of different sizes and compressing them"
split_and_compress
cd ..

echo -e "$BLUE============== Preparing RandomL files ==============$NC"
mkdir -p random01lines
cd random01lines

cat /dev/urandom | tr -dc "0123456789\n" | dd bs=10M count=50 iflags=fullblock 2>/dev/null > tmp.txt
cat tmp.txt | tr "2" "0" | tr "4" "0" | tr "6" "0" | tr "8" "0" | tr "3" "1" | tr "5" "1" | tr "7" "1" | tr "9" "1" > random.txt
rm tmp.txt 
echo "Data created!!"

iconv --to-code US-ASCII -c random.txt > original.txt 
rm random.txt

echo "Generating files of different sizes and compressing them"
split_and_compress
cd ..

echo "ALL FILES GENERATED"