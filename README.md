# Regular Expression Search on Compressed Text

What is it?
**zearch** is a regular expression engine that takes in input a regular expression and a grammar-based compressed text and returns every line of the uncompressed text containing a match for the regular expression.

## Limitations

- no match across lines
- no support invert match option
- only regular languages (like RE2) → e.g. no backreferences
- no zero-width character
- no named character classes (e.g. alnum, digit, lower,…)
- no UTF8 support, only ASCII characters
- no highlighted output, only matching line are reported in full

## Compiling

### Installing libfa
Clone the [*augeas project*](https://github.com/hercules-team/augeas) repository.
```
git clone git@github.com:hercules-team/augeas.git
```
From the root folder run
```
./autogen.sh
make
sudo make install
```

### Compiling Zearch
From the root folder of this repository run `make zearc stats debug` which generates three executables:
* *zearch* is the main program.
* *stats* works as zearch but produces some statistical information about memory usage.
* *debug* prints a lof of information for debugging through stderr.

These three tools are invoked in the same way:
```
./{zearch,debug,stats} [-m] <option> <input_regex> <input_file>
```
where
* *-m* is an optional argument. When present, the program will determinize and minimize the automaton, following the algorithm used by *libfa*. Note that this option does not always improves performance.
* *option* can be `-c`, `-l` or `-a` to print the number of matches, the matching lines or both, respectively.
* *input_regex* is a regular expression following the format accepted by *libfa*.
* *input_file* is a [repair](https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/re-pair/repair110811.tar.gz)-compressed file.


## Comparison with other tools
We have compared the performance of **zearch** with the state of the art approach for regular expression matching on compressed text.
Due to the limited functionality of our tool, the comparison only considers the running time required by these tools to report the number of lines in the original file containing a match.
For the experiments the state of the art is represented by the following command
```
zstd -dc compressed_file.Z | {grep,rg} -c regex
```
The experiments show that our tool outperforms the state of the art, even when decompression and search are done in parallel.
The detailed results of this comparison are available [here]()