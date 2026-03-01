#!/usr/bin/env python3

# Computes the average and the confidence interval with significance alpha=0.05

import sys
from math import sqrt

Z = 1.96 # P(X <= Z) = (1-alpha/2) for X = N(0,1)
T = [0, 0, 0, 0, 2.7764, 0, 0, 0, 0, 2.2622, 0, 0, 0, 0, 2.1448, 0, 0, 0, 0, 2.0930, 0, 0, 0, 0, 2.0639, 0, 0, 0, 0, 2.0452] # T[i]: P(X <= T[i]) = (1-alpha/2) for X a Student's t with i degrees of freedom. I have just filled some values.
file_name = sys.argv[1]

try:
	file = open(file_name, "r")
	data = [int(x) for x in file.read().split('\n') if x.strip()]
except (FileNotFoundError, IOError):
	data = []

n = len(data)

if n == 0:
	print("{\"avg\": -1, \"err\": 0}")
	sys.exit(0)

avg = sum(data) * 1.0 / n

if n == 1:
	print("{\"avg\": %.3f, \"err\": 0}" % avg)
	sys.exit(0)

s = sqrt(sum([(x - avg) ** 2 for x in data]) / (n - 1))

if n >= 30:
	interval = Z * s / sqrt(n)
else:
	interval = T[n - 1] * s / sqrt(n)

print("{\"avg\": %.3f, \"err\": %.3f}" % (avg, interval))
