#! /usr/bin/python

import json
import sys
from collections import OrderedDict

if len(sys.argv) != 3:
	print "Wrong input."
	print "./cactus-plot input_file output_file"
	sys.exit(-1)

with open(sys.argv[1]) as data_file:
	json_data = json.load(data_file,object_pairs_hook=OrderedDict)

# print json_data
sorted_lists = dict()
first = True
sorted_keys = []

ignore=["Regex", "MatchesZ", "MatchesR", "MatchesGG", "MatchesH", "MatchesN", "MatchesL", "zstd_s","lz4_s","lzw_s","repair_s","gzip_s","zstd","lz4","LZW","gzip", "repair"]

for run in json_data:
	if run["Regex"] == "All":
		break
	if first:
		first = False
		for k in run:
			if k not in ignore:
				sorted_lists[k] = [run[k]["avg"]]
				sorted_keys.append(k)
	else:
		for k in run:
			if k not in ignore:
				sorted_lists[k].append(run[k]["avg"])

for k in sorted_lists:
	sorted_lists[k] = [x for x in sorted_lists[k] if x != 0]
	sorted_lists[k].sort()

# print "sorted lists"
# print sorted_lists
# print "sorted keys"
# print sorted_keys

for k in sorted_keys:
	totalsum = 0
	for i in range(len(sorted_lists[k])):
		totalsum += sorted_lists[k][i]
		sorted_lists[k][i] = totalsum

# print "sorted lists"
# print sorted_lists

# print "conversion"
maximum = max([len(sorted_lists[x]) for x in sorted_lists])

tools = ["zearch","grep","ripgrep","hyperscan","zhs_lz4_p","zhs_zstd_p","zgrep_lz4_p","zgrep_zstd_p","zrg_lz4_p","zrg_zstd_p"]
with open(sys.argv[2], 'w') as data_file:
	data_file.write("[")
	for i in range(maximum):
		data_file.write("{")
		data_file.write("\"Regex\": "+str(i+1)+",")
		for k in tools:
			if i < len(sorted_lists[k]):
				data_file.write("\""+k+"\": " + str(sorted_lists[k][i]) + ",")

		data_file.write("\"Ignore\": 0")
		if i != maximum-1:
			data_file.write("},")
		else:
			data_file.write("}]")

